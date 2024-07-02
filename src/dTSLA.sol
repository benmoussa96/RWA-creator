// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { OracleLib, AggregatorV3Interface } from "./libraries/OracleLib.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import { FunctionsClient } from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import { FunctionsRequest } from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";

/*
 * @title dTSLA
 * @author Ben Moussa
 */
contract dTSLA is ERC20, Pausable, ConfirmedOwner, FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;
    using OracleLib for AggregatorV3Interface;
    using Strings for uint256;

    error dTSLA__NotEnoughCollateral();
    error dTSLA__InvalidMintAmount();
    error dTSLA__MinimumRedemptionAmountNotMet();
    error dTSLA__TransferFailed();

    enum MintOrRedeem { mint, redeem }

    struct dTSLARequest {
        uint256 amountOfToken;
        address requester;
        MintOrRedeem mintOrRedeem;
    }

    bytes32 s_donId;
    uint64 immutable i_subId;
    string private s_mintSourceCode;
    string private s_redeemSourceCode;
    uint32 private constant GAS_LIMIT = 300_000;

    uint256 s_portfolioBalance;

    address public i_tslaUsdFeed;
    address public i_usdcUsdFeed;
    address public i_redemptionCoin;
    uint256 private immutable i_redemptionCoinDecimals;

    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 public constant COLLATERAL_RATIO = 200; // 200% collateral ratio
    uint256 public constant COLLATERAL_PRECISION = 100;

    uint256 public constant MINIMUM_REDEMPTION_COIN_REDEMPTION_AMOUNT = 100e18;

    mapping(bytes32 requestId => dTSLARequest request) private s_requestIdToRequest;
    mapping(address user => uint256 availableWithdrawlAmount) private s_userToAvailableWithrawlAmount;

    constructor(
        address functionsRouter, 
        string memory mintSourceCode, 
        string memory redeemSourceCode, 
        bytes32 donId, 
        uint64 subId, 
        address tslaPriceFeed,
        address usdcPriceFeed,
        address redemptionCoin
    ) 
        ERC20("Backed TSLA", "bTSLA") 
        ConfirmedOwner(msg.sender) 
        FunctionsClient(functionsRouter) 
    {
        s_donId = donId;
        i_subId = subId;
        s_mintSourceCode = mintSourceCode;
        s_redeemSourceCode = redeemSourceCode;
        i_tslaUsdFeed = tslaPriceFeed;
        i_usdcUsdFeed = usdcPriceFeed;
        i_redemptionCoin = redemptionCoin;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// 2 transactions
    /// Sends an HTTP request to:
    /// 1. See how much TSLA is bought
    /// 2. If wnough TSLA is in the Alpaca account, mint dTSLA
    function sendMintRequest(uint256 amountOfTokensToMint) external onlyOwner whenNotPaused returns (bytes32 requestId) {
        if (amountOfTokensToMint != 0) {
            revert dTSLA__InvalidMintAmount();
        }

        // If they want to mint $100 and the portfolio has $200, then that's cool
        if (_getCollateralRatioAdjustedTotalBalance(amountOfTokensToMint) > s_portfolioBalance) {
            revert dTSLA__NotEnoughCollateral();
        }

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_mintSourceCode);
        bytes32 _requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, s_donId);
        s_requestIdToRequest[_requestId] = dTSLARequest(amountOfTokensToMint, msg.sender, MintOrRedeem.mint);

        return _requestId;
    }

    /// @notice User sends a request to sell TSLA for USDC (redemtionToken)
    /// This will have the chainlink function call our Alpaca (bank) to:
    /// 1. Sell TSLA on the brokerage
    /// 2. Buy USDC on the brokerage
    /// 3. Send USDC to this contract for the user to withdraw
    function sendRedeemRequest(uint256 dTslaAmount) external {
        uint256 tslaAmountInUsdc = getUsdcValueOfUsd(getUsdValueOfTsla(dTslaAmount));
        if (tslaAmountInUsdc < MINIMUM_REDEMPTION_COIN_REDEMPTION_AMOUNT) {
            revert dTSLA__MinimumRedemptionAmountNotMet();
        }

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_redeemSourceCode);

        string[] memory args = new string[](2);
        args[0] = dTslaAmount.toString();
        args[1] = tslaAmountInUsdc.toString();
        req.setArgs(args);

        bytes32 _requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, s_donId);
        s_requestIdToRequest[_requestId] = dTSLARequest(dTslaAmount, msg.sender, MintOrRedeem.redeem);

        _burn(msg.sender, dTslaAmount);
    }

    function withdraw() external {
        uint256 amountAvailableToWithdraw = s_userToAvailableWithrawlAmount[msg.sender];
        s_userToAvailableWithrawlAmount[msg.sender] = 0;

        bool success = ERC20(i_redemptionCoin).transfer(msg.sender, amountAvailableToWithdraw);
        
        if(!success) {
            revert dTSLA__TransferFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Callback function for fulfilling a request
    /// @param requestId The ID of the request to fulfill
    /// @param response The HTTP response data
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory /* err */
    ) internal override {
        if (s_requestIdToRequest[requestId].mintOrRedeem == MintOrRedeem.mint) {
            _mintFulFillRequest(requestId,response);
        } else {
            _redeemFulFillRequest(requestId,response);
        }
    }

    /// Return the amount of TSLA (in USD) is stored in our broker
    /// If we have enough of TSLA collateral, mint the dTSLA tokens
    function _mintFulFillRequest(bytes32 requestId, bytes memory response) internal {
        uint256 amountOfTokensToMint = s_requestIdToRequest[requestId].amountOfToken;
        s_portfolioBalance = uint256(bytes32(response));

        // if TSLA collateral > dTSLA to min -> mint
        // 1. How much TSLA in $$$ do we have?
        // 2. How much TSLA in $$$ are we minting?
        if (_getCollateralRatioAdjustedTotalBalance(amountOfTokensToMint) > s_portfolioBalance) {
            revert dTSLA__NotEnoughCollateral();
        }

        if (amountOfTokensToMint != 0) {
            _mint(s_requestIdToRequest[requestId].requester, amountOfTokensToMint);
        }
    }

    function _redeemFulFillRequest(bytes32 requestId, bytes memory response) internal {
        // This is going to have redemptioncoindecimals decimals
        uint256 usdcAmount = uint256(bytes32(response));
        uint256 usdcAmountWad;
        if (i_redemptionCoinDecimals < 18) {
            usdcAmountWad = usdcAmount * (10 ** (18 - i_redemptionCoinDecimals));
        }

        // If 0 USDC was redeemed, refund user
        if (usdcAmount == 0) {
            uint256 amountOfdTSLABurned = s_requestIdToRequest[requestId].amountOfToken;
            _mint(msg.sender, amountOfdTSLABurned);
            return;
        }

        s_userToAvailableWithrawlAmount[s_requestIdToRequest[requestId].requester] += usdcAmount;
    }
    
    function _getCollateralRatioAdjustedTotalBalance(uint256 amountOfTokensToMint) internal view returns (uint256) {
        uint256 calculatedNewTotalValue = getCalculatedNewTotalValue(amountOfTokensToMint);
        return (calculatedNewTotalValue * COLLATERAL_RATIO) / COLLATERAL_PRECISION;
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW AND PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getTslaPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(i_tslaUsdFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION;
    }

    function getUsdcPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(i_usdcUsdFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION;
    }

    function getUsdValueOfTsla(uint256 tslaAmount) public view returns (uint256) {
        return (tslaAmount * getTslaPrice()) / PRECISION;
    }

    function getUsdcValueOfUsd(uint256 usdAmount) public view returns (uint256) {
        return (usdAmount * getUsdcPrice()) / PRECISION;
    }

    function getCalculatedNewTotalValue(uint256 addedNumberOfTsla) public view returns (uint256) {
        return ((totalSupply() + addedNumberOfTsla) * getTslaPrice()) / PRECISION;
    }

    function getRequest(bytes32 requestId) public view returns (dTslaRequest memory) {
        return s_requestIdToRequest[requestId];
    }

    function getWithdrawalAmount(address user) public view returns (uint256) {
        return s_userToWithdrawalAmount[user];
    }
}
