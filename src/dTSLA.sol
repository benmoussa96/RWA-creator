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

    string private s_mintSourceCode;

    uint256 s_portfolioBalance;

    address public i_tslaUsdFeed;

    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 public constant COLLATERAL_RATIO = 200; // 200% collateral ratio
    uint256 public constant COLLATERAL_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;


    constructor(address functionsRouter, string memory mintSourceCode) 
        ERC20("Backed TSLA", "bTSLA") 
        ConfirmedOwner(msg.sender) 
        FunctionsClient(functionsRouter) 
    {
        s_mintSourceCode = mintSourceCode;
    }

    /// 2 transactions
    /// Sends an HTTP request to:
    /// 1. See how much TSLA is bought
    /// 2. If wnough TSLA is in the Alpaca account, mint dTSLA
    function sendMintRequest(uint256 amountOfTokensToMint) external onlyOwner whenNotPaused returns(bytes32 requestId) {
        // they want to mint $100 and the portfolio has $200 - then that's cool
        if (_getCollateralRatioAdjustedTotalBalance(amountOfTokensToMint) > s_portfolioBalance) {
            revert dTSLA__NotEnoughCollateral();
        }

        FunctionsRequest.Request memory req;

    }

    function _mintFulFillRequest() internal {

    }

    /// @notice User sends a request to sell TSLA for USDC (redemtionToken)
    /// This will have the chainlink function call our Alpaca (bank) to:
    /// 1. Sell TSLA on the brokerage
    /// 2. Buy USDC on the brokerage
    /// 3. Send USDC to this contract for the user to withdraw
    function sendRedeemRequest() external {

    }

    function _redeemFulFillRequest() internal {

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
