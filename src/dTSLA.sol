// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

/*
 * @title dTSLA
 * @author Ben Moussa
 */
contract dTSLA is ConfirmedOwner {
    /// 2 transactions
    /// Sends an HTTP request to:
    /// 1. See how much TSLA is bought
    /// 2. If wnough TSLA is in the Alpaca account, mint dTSLA
    function sendMintRequest(uint256 amount) external {
        
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
}
