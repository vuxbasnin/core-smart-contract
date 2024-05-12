// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./../../Base/strategies/BaseRestakingStrategy.sol";

contract RenzoZircuitRestakingStrategy is BaseRestakingStrategy {
    IWithdrawRestakingPool private renzoWithdrawRestakingPool;
    IWithdrawRestakingPool private zircuitwithdrawRestakingPool;

    IRenzoRestakeProxy private renzoRestakeProxy;
    IZircuitRestakeProxy private zircuitRestakeProxy;
    IERC20 private stakingToken;

    function ethRestaking_Initialize(
        address _restakingToken,
        address _swapAddress,
        address _usdcAddress,
        address _ethAddress,
        address[] memory _restakingPoolAddresses,
        address _zircuitwithdrawRestakingPoolAddress
    ) internal {
        super.ethRestaking_Initialize(_restakingToken, _swapAddress, _usdcAddress, _ethAddress);

        renzoRestakeProxy = IRenzoRestakeProxy(_restakingPoolAddresses[0]);
        zircuitRestakeProxy = IZircuitRestakeProxy(_restakingPoolAddresses[1]);
        zircuitwithdrawRestakingPool = IWithdrawRestakingPool(_zircuitwithdrawRestakingPoolAddress);
    }

    function syncRestakingBalance() internal override{
        uint256 ezEthOnZircuit = zircuitRestakeProxy.balanceOf(address(restakingToken), address(this));
        uint256 ezEthOnContract = restakingToken.balanceOf(address(this));
        uint256 ethAmount = (ezEthOnZircuit + ezEthOnContract) * swapProxy.getPriceOf(address(restakingToken), address(ethToken)) / 1e18;
        restakingStratState.totalBalance = restakingStratState.unAllocatedBalance + ethAmount * swapProxy.getPriceOf(address(ethToken), address(usdcToken)) / 1e18;
    }

    function depositToRestakingProxy(uint256 ethAmount) internal override {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        ethToken.approve(address(swapProxy), ethAmount);
        uint256 ezEthAmount = swapProxy.swapTo(
            address(this),
            address(ethToken),
            ethAmount,
            address(restakingToken),
            fees["RExTOKEN_ETH"]
        );

        restakingToken.approve(address(zircuitRestakeProxy), ezEthAmount);
        zircuitRestakeProxy.depositFor(address(restakingToken), address(this), ezEthAmount);
    }

    function withdrawFromRestakingProxy(uint256 ethAmount, uint8 buffer, uint8 bufferDecimals) internal override {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        uint256 stakingTokenAmount = buffer * ethAmount * swapProxy.getPriceOf(address(restakingToken), address(ethToken)) / 10 ** (18 + bufferDecimals);

        zircuitwithdrawRestakingPool.withdraw(stakingTokenAmount);

        // Swap exact output ethAmount from restakingToken withdrawn from zircuit
        restakingToken.approve(address(swapProxy), stakingTokenAmount);

        swapProxy.swapToWithOutput(
            address(this),
            address(restakingToken),
            ethAmount,
            address(restakingToken),
            fees["RExTOKEN_ETH"]
        );
    }

    function updateZircuitwithdrawRestaking(address _zircuitwithdrawRestakingPoolAddress) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        zircuitwithdrawRestakingPool = IWithdrawRestakingPool(_zircuitwithdrawRestakingPoolAddress);
    }
}