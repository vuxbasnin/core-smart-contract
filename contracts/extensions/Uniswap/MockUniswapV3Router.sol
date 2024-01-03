// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../interfaces/ISwapRouter.sol";

contract MockSwapRouter is ISwapRouter {

    // Mock function to mimic swapping tokens at a 1:1 rate
    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable override returns (uint amountOut) {
        // Validate that the deadline has not passed
        require(params.deadline >= block.timestamp, "Transaction expired");

        // Simulate a 1:1 swap rate
        amountOut = params.amountIn;

        // Ensure that the output is greater than or equal to the minimum amount out specified
        require(amountOut >= params.amountOutMinimum, "Insufficient output amount");

        // Mock transfer of the output token to the recipient
        // Note: In a real scenario, you would interact with the actual token contracts.
        // This is a simple mock, so we're skipping token transfer logic.

        return amountOut;
    }

    function factory() external view returns (address){
        
    }
}
