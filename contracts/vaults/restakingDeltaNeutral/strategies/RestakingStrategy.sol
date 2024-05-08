// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../../../interfaces/IRestakingPool.sol";
import "../../../extensions/RockOnyxAccessControl.sol";
import "../../../extensions/Restaking/RenzoRestakingPool.sol";
import "../../../extensions/Restaking/ZircuitRestakingPool.sol";
import "../structs/RestakingDeltaNeutralStruct.sol";
import "../../../interfaces/ISwapProxy.sol";
import "hardhat/console.sol";

abstract contract BaseRestakingStrategy is RockOnyxAccessControl, ReentrancyGuard {
    IERC20 usdcToken;
    IERC20 ethToken;

    address public admin;
    IERC20 internal restakingToken;
    ISwapProxy internal swapProxy;
    address[] internal restakingPoolAddresses;

    EthRestakingState internal restakingStratState;

    // Events
    event Deposited(address indexed proxy, uint256 amount);
    event Withdrawn(address indexed proxy, uint256 amount);

    constructor() {}

    function ethRestaking_Initialize(
        address _restakingToken,
        address _swapAddress,
        address _usdcAddress,
        address _ethAddress,
        address[] memory _restakingPoolAddresses
    ) internal virtual {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(_restakingToken != address(ethToken), "Invalid token address");

        swapProxy = ISwapProxy(_swapAddress);
        usdcToken = IERC20(_usdcAddress);
        ethToken = IERC20(_ethAddress);
        restakingToken = IERC20(_restakingToken);
        restakingPoolAddresses = _restakingPoolAddresses;
    }

    // Function to handle deposits to the staking strategies and allocate points
    function depositToRestakingStrategy(uint256 amount) internal {
        require(amount > 0, "Amount must be greater than 0");

        restakingStratState.unAllocatedBalance += amount;
    }

    function openPosition(uint256 ethAmount) external nonReentrant {
        _auth(ROCK_ONYX_OPTIONS_TRADER_ROLE);

        require(
            restakingStratState.unAllocatedBalance > 0,
            "Insufficient unallocated balance"
        );

        // Swap USDC to ETH
        usdcToken.approve(
            address(swapProxy),
            restakingStratState.unAllocatedBalance
        );
        uint256 actualEthAmount = swapProxy.swapToWithOutput(
            address(this),
            address(usdcToken),
            ethAmount,
            address(ethToken)
        );

        require(
            actualEthAmount >= ethAmount,
            "Insufficient ETH amount after swap"
        );

        // Update unAllocatedBalance
        restakingStratState.unAllocatedBalance -= usdcToken.balanceOf(
            address(this)
        );

        // Call depositToRestakingProxy
        depositToRestakingProxy(ethAmount);
    }

    function closePosition(uint256 ethAmount) external nonReentrant {
        _auth(ROCK_ONYX_OPTIONS_TRADER_ROLE);

        // Get price of restakingToken in ethToken
        uint256 price = swapProxy.getPriceOf(
            address(restakingToken),
            address(ethToken)
        );

        // Calculate stakingToken amount need to withdrawal from zircuit pool
        uint256 stakingTokenAmount = (ethAmount * price) / 1e18;

        withdrawFromRestakingProxy(stakingTokenAmount);

        // Get the balance of restakingToken of address(this)
        uint256 actualWithdrawnAmount = restakingToken.balanceOf(address(this));

        // Swap exact output ethAmount from restakingToken withdrawn from zircuit
        restakingToken.approve(address(swapProxy), actualWithdrawnAmount);
        uint256 actualEthAmount = swapProxy.swapToWithOutput(
            address(this),
            address(restakingToken),
            actualWithdrawnAmount,
            address(restakingToken)
        );

        require(
            actualEthAmount >= ethAmount,
            "Insufficient ETH amount after swap"
        );

        // Swap ETH to USDC
        ethToken.approve(address(swapProxy), actualEthAmount);
        uint256 actualUsdcAmount = swapProxy.swapTo(
            address(this),
            address(ethToken),
            actualEthAmount,
            address(usdcToken)
        );
        console.log("actualUsdcAmount %s", actualUsdcAmount);
        // Update unAllocatedBalance
        restakingStratState.unAllocatedBalance += usdcToken.balanceOf(
            address(this)
        );
    }

    function depositToRestakingProxy(uint256 ethAmount) internal virtual nonReentrant {}
    function withdrawFromRestakingProxy(uint256 ethAmount) internal virtual nonReentrant {}

    function syncRestakingBalance() internal {
        // Get price of ezETH in ETH
        uint256 restakingTokenEthPrice = swapProxy.getPriceOf(
            address(restakingToken),
            address(ethToken)
        );

        // Get balance of address(this) of ezETH
        uint256 restakingTokenBalance = restakingToken.balanceOf(address(this));

        // Calculate ETH amount from balance of ezETH
        uint256 ethAmount = (restakingTokenBalance * restakingTokenEthPrice) / 1e18;

        // Calculate USDC value of ETH amount
        uint256 ethPrice = swapProxy.getPriceOf(
            address(restakingToken),
            address(ethToken)
        );
        uint256 ethValue = (ethAmount * ethPrice) / 1e18;

        // Update restakingStratState
        restakingStratState.totalBalance = ethValue;
    }

    function acquireFundsFromRestakingStrategy(
        uint256 amount
    ) internal returns (uint256) {
        uint256 unAllocatedBalance = restakingStratState.unAllocatedBalance;
        require(amount <= unAllocatedBalance, "INVALID_ACQUIRE_AMOUNT");

        restakingStratState.unAllocatedBalance -= amount;
        restakingStratState.totalBalance -= amount;
        return amount;
    }

    function getTotalRestakingTvl() internal view returns (uint256) {
        return restakingStratState.totalBalance;
    }

    /**
     * @dev Retrieves the unallocated balance in the Ethereum Stake & Lend strategy.
     * @return The unallocated balance in the Ethereum Stake & Lend strategy.
     */
    function getEthStakingUnAllocatedBalance() external view returns (uint256) {
        return restakingStratState.unAllocatedBalance;
    }
}
