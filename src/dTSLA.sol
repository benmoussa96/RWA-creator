// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { OracleLib, AggregatorV3Interface } from "./libraries/OracleLib.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
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

    error dTSLA__NotEnoughCollateral();
    error dTSLA__InvalidMintAmount();

    enum MintOrRedeem { mint, redeem }

    struct dTSLARequest {
        uint256 amountOfToken;
        address requester;
        MintOrRedeem mintOrRedeem;
    }

    bytes32 s_donID;
    uint64 immutable i_subId;
    string private s_mintSourceCode;
    uint32 private constant GAS_LIMIT = 300_000;

    address public i_tslaUsdFeed;

    uint256 s_portfolioBalance;

    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 public constant COLLATERAL_RATIO = 200; // 200% collateral ratio
    uint256 public constant COLLATERAL_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;

    mapping(bytes32 requestId => dTSLARequest request) private s_requestIdToRequest;

    constructor(address functionsRouter, string memory mintSourceCode, bytes32 donId, uint64 subId, address tslaPriceFeed) 
        ERC20("Backed TSLA", "bTSLA") 
        ConfirmedOwner(msg.sender) 
        FunctionsClient(functionsRouter) 
    {
        s_donID = donId;
        i_subId = subId;
        s_mintSourceCode = mintSourceCode;
        i_tslaUsdFeed = tslaPriceFeed;
    }

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
        bytes32 _requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, s_donID);
        s_requestIdToRequest[_requestId] = dTSLARequest(amountOfTokensToMint, msg.sender, MintOrRedeem.mint);

        return _requestId;
    }

    /// @notice User sends a request to sell TSLA for USDC (redemtionToken)
    /// This will have the chainlink function call our Alpaca (bank) to:
    /// 1. Sell TSLA on the brokerage
    /// 2. Buy USDC on the brokerage
    /// 3. Send USDC to this contract for the user to withdraw
    function sendRedeemRequest() external {

    }

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

    }
    
    function _getCollateralRatioAdjustedTotalBalance(uint256 amountOfTokensToMint) internal view returns (uint256) {
        uint256 calculatedNewTotalValue = getCalculatedNewTotalValue(amountOfTokensToMint);
        return (calculatedNewTotalValue * COLLATERAL_RATIO) / COLLATERAL_PRECISION;
    }

    function getTslaPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(i_tslaUsdFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION;
    }

    function getCalculatedNewTotalValue(uint256 addedNumberOfTsla) public view returns (uint256) {
        return ((totalSupply() + addedNumberOfTsla) * getTslaPrice()) / PRECISION;
    }
}
