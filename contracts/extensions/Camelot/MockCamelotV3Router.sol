// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../interfaces/CamelotSwap/ICamelotSwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

contract MockSwapRouter is ICamelotSwapRouter {
    // Mock function to mimic swapping tokens at a 1:1 rate
    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable override returns (uint amountOut) {
        require(
            IERC20(params.tokenIn).transferFrom(
                msg.sender,
                address(this),
                params.amountIn
            ),
            "Transfer failed"
        );
        // Simulate a 1:1 swap rate
        amountOut = params.amountIn;

        // Ensure that the output is greater than or equal to the minimum amount out specified
        require(
            amountOut >= params.amountOutMinimum,
            "Insufficient output amount"
        );

        console.log(
            "[MockSwapRouter] balanceOf %s",
            IERC20(params.tokenIn).balanceOf(address(this))
        );
        // Assuming tokenOut is already approved to this contract
        require(
            IERC20(params.tokenOut).transfer(params.recipient, amountOut),
            "Transfer failed"
        );
        console.log("[MockSwapRouter] exactInputSingle transfered");
        return amountOut;
    }

    function exactOutputSingle(
        ExactOutputSingleParams calldata params
    ) external payable override returns (uint amountIn) {
        require(
            IERC20(params.tokenIn).transferFrom(
                msg.sender,
                address(this),
                params.amountInMaximum
            ),
            "Transfer failed"
        );

        // Simulate a 1:1 swap rate
        amountIn = params.amountOut;

        // Ensure that the output is greater than or equal to the minimum amount out specified
        require(
            amountIn >= params.amountInMaximum,
            "Insufficient output amount"
        );

        console.log(
            "[MockSwapRouter] balanceOf %s",
            IERC20(params.tokenIn).balanceOf(address(this))
        );
        // Assuming tokenOut is already approved to this contract
        require(
            IERC20(params.tokenOut).transfer(
                params.recipient,
                params.amountOut
            ),
            "Transfer failed"
        );
        console.log("[MockSwapRouter] exactInputSingle transfered");
        return amountIn;
    }

    function factory() external view returns (address) {}
}
