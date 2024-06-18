// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../../../interfaces/IKelpRestakeProxy.sol";
import "../../../../interfaces/IZircuitRestakeProxy.sol";
import "../../../../interfaces/IWETH.sol";
import "./../../Base/strategies/BaseRestakingStrategy.sol";
import "./../../Base/BaseSwapVault.sol";
import "../KelpDaoProxy/KelpDaoProxy.sol";

contract KelpZircuitRestakingStrategy is BaseRestakingStrategy {
    IKelpRestakeProxy private kelpRestakeProxy;
    IZircuitRestakeProxy private zircuitRestakeProxy;
    KelpDaoProxy private kelpDaoProxy;
    IERC20 private stakingToken;
    string private refId;

    function ethRestaking_Initialize(
        address _restakingToken,
        address _usdcAddress,
        address _ethAddress,
        address[] memory _restakingPoolAddresses,
        string memory _refId,
        address _swapAddress,
        address[] memory _token0s,
        address[] memory _token1s,
        uint24[] memory _fees
    ) internal {
        super.ethRestaking_Initialize(_restakingToken, _usdcAddress, _ethAddress, _swapAddress, _token0s, _token1s, _fees);

        refId = _refId;
        kelpRestakeProxy = IKelpRestakeProxy(_restakingPoolAddresses[0]);
        kelpDaoProxy = new KelpDaoProxy(_restakingPoolAddresses[1], swapProxy, restakingToken);
    }

    function syncRestakingBalance() internal override{
        uint256 restakingTokenAmount = restakingToken.balanceOf(address(this));
        if(address(zircuitRestakeProxy) != address(0)){
            restakingTokenAmount += zircuitRestakeProxy.balance(address(restakingToken), address(this));
        }

        uint256 ethAmount = restakingTokenAmount * swapProxy.getPriceOf(address(restakingToken), address(ethToken)) / 1e18;
        restakingState.totalBalance = restakingState.unAllocatedBalance + ethAmount * swapProxy.getPriceOf(address(ethToken), address(usdcToken)) / 1e18;
    }

    function depositToRestakingProxy(uint256 ethAmount) internal override {
        kelpDaoProxy.depositToRestakingProxy(ethAmount, refId);
    }

    function withdrawFromRestakingProxy(uint256 ethAmount) internal override {
        kelpDaoProxy.withdrawFromRestakingProxy(ethAmount);
    }

    function updateKelpWithdrawRestaking(address _kelpWithdrawRestakingPoolAddress) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        kelpDaoProxy.updateKelpWithdrawRestaking(_kelpWithdrawRestakingPoolAddress);
    }

    function updateRestakingPoolAddresses(address[] memory _restakingPoolAddresses) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        kelpRestakeProxy = IKelpRestakeProxy(_restakingPoolAddresses[0]);
        kelpDaoProxy.updateZirCuitRestakeProxy(_restakingPoolAddresses[1]);
    }
}