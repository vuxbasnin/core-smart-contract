// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../../../../interfaces/IWithdrawRestakingPool.sol";
import "../../../../extensions/RockOnyxAccessControl.sol";
import "../../../../extensions/Restaking/RenzoWithdrawRestakingPool.sol";
import "../../../../extensions/Restaking/ZircuitWithdrawRestakingPool.sol";
import "../../../../extensions/Uniswap/Uniswap.sol";
import "../../structs/RestakingDeltaNeutralStruct.sol";
import "hardhat/console.sol";

abstract contract BaseRestakingStrategy is RockOnyxAccessControl, ReentrancyGuard {
    IERC20 usdcToken;
    IERC20 ethToken;
    IERC20 internal restakingToken;
    UniSwap internal swapProxy;
    address[] internal restakingPoolAddresses;
    // [ETH_USD, EZETH_ETH]
    mapping(string => uint24) internal fees;
    EthRestakingState internal restakingStratState;

    // Events
    event Deposited(address indexed proxy, uint256 amount);
    event Withdrawn(address indexed proxy, uint256 amount);

    event PositionOpened(uint256 usdcAmount, uint256 ethAmount);
    event PositionClosed(uint256 ethAmount, uint256 usdcAmount);

    constructor() {}

    function ethRestaking_Initialize(
        address _restakingToken,
        address _swapAddress,
        address _usdcAddress,
        address _ethAddress
    ) internal virtual {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        swapProxy = UniSwap(_swapAddress);
        usdcToken = IERC20(_usdcAddress);
        ethToken = IERC20(_ethAddress);
        restakingToken = IERC20(_restakingToken);
        fees["ETH_USD"] = 500;
        fees["RExTOKEN_ETH"] = 100;
    }

    // Function to handle deposits to the staking strategies and allocate points
    function depositToRestakingStrategy(uint256 amount) internal {
        require(amount > 0, "INVALID_AMOUNT");

        restakingStratState.unAllocatedBalance += amount;
        restakingStratState.totalBalance += amount;
    }

    function openPosition(uint256 ethAmount) external nonReentrant {
        _auth(ROCK_ONYX_OPTIONS_TRADER_ROLE);
        require(restakingStratState.unAllocatedBalance > 0, "INSUFICIENT_BALANCE");

        usdcToken.approve(address(swapProxy), restakingStratState.unAllocatedBalance);
       
        uint256 usedUsdAmount = swapProxy.swapToWithOutput(
            address(this),
            address(usdcToken),
            ethAmount,
            address(ethToken), 
            fees["ETH_USD"]
        );

        restakingStratState.unAllocatedBalance -= usedUsdAmount;
        depositToRestakingProxy(ethAmount);

        emit PositionOpened(usedUsdAmount, ethAmount);
    }

    function closePosition(uint256 ethAmount, uint8 buffer, uint8 bufferDecimals) external nonReentrant {
        _auth(ROCK_ONYX_OPTIONS_TRADER_ROLE);

        withdrawFromRestakingProxy(ethAmount, buffer, bufferDecimals);
        ethToken.approve(address(swapProxy), ethAmount);
        uint256 actualUsdcAmount = swapProxy.swapTo(
            address(this),
            address(ethToken),
            ethAmount,
            address(usdcToken),
            fees["ETH_USD"]
        );

        restakingStratState.unAllocatedBalance += actualUsdcAmount;
        emit PositionClosed(ethAmount, actualUsdcAmount);
    }

    function depositToRestakingProxy(uint256 ethAmount) internal virtual nonReentrant {}
    
    function withdrawFromRestakingProxy(uint256 ethAmount, uint8 buffer, uint8 bufferDecimals) internal virtual nonReentrant {}

    function syncRestakingBalance() internal virtual{

        uint256 ethAmount = restakingToken.balanceOf(address(this)) * swapProxy.getPriceOf(address(restakingToken), address(ethToken)) / 1e18;
        restakingStratState.totalBalance = restakingStratState.unAllocatedBalance + ethAmount * swapProxy.getPriceOf(address(restakingToken), address(ethToken)) / 1e18;
    }

    function getTotalRestakingTvl() internal view returns (uint256) {
        return restakingStratState.totalBalance;
    }

    function acquireFundsFromRestakingStrategy(uint256 amount) internal returns (uint256){
        uint256 unAllocatedBalance = restakingStratState.unAllocatedBalance;
        require(amount <= unAllocatedBalance, "INVALID_ACQUIRE_AMOUNT");

        restakingStratState.unAllocatedBalance -= amount;
        restakingStratState.totalBalance -= amount;
        return amount;
    }

    /**
     * @dev Retrieves the unallocated balance in the Ethereum Stake & Lend strategy.
     * @return The unallocated balance in the Ethereum Stake & Lend strategy.
     */
    function getEthStakingState() external view returns (EthRestakingState memory) {
        return restakingStratState;
    }
}
