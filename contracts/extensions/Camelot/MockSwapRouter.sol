// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../interfaces/ISwapRouter.sol";

contract MockSwapRouter is ISwapRouter {
    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable override returns (uint amountOut) {
        // In a real swap, logic to perform the swap and determine amountOut would go here.
        // For a mock, you can simply return a fixed value or a manipulated version of input for testing.

        // Example: Return the input amount as the output amount for simplicity
        return params.amountIn;
    }
}
