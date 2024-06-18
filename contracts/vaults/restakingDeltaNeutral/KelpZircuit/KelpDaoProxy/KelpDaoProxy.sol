// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../../interfaces/IKelpRestakeProxy.sol";
import "../../../../interfaces/IZircuitRestakeProxy.sol";
import "../../../../interfaces/IWETH.sol";
import "../../../../extensions/Uniswap/Uniswap.sol";
import "../../Base/BaseSwapVault.sol";
import "../Base/BaseKelpRenzoProxy.sol";

contract KelpDaoProxy is BaseKelpRenzoProxy, BaseSwapVault {
    IKelpRestakeProxy private kelpRestakeProxy;
    IERC20 private ethToken;

    constructor(address _addressContractZircuit, UniSwap _swapProxy, IERC20 _restakingToken) {
        baseKelpRenzoProxyInit(_addressContractZircuit, _swapProxy, _restakingToken);
    }

    function depositToRestakingProxy(uint256 ethAmount, string memory refId) external override {
        if(address(kelpRestakeProxy) != address(0)) {
            IWETH(address(ethToken)).withdraw(ethAmount);

            // arbitrum
            // kelpRestakeProxy.swapToRsETH{value: ethAmount}(0, refId);

            // ethereum
            kelpRestakeProxy.depositETH{value: ethAmount}(0, refId);
        }else{
            ethToken.approve(address(swapProxy), ethAmount);
            swapProxy.swapTo(
                address(this),
                address(ethToken),
                ethAmount,
                address(restakingToken),
                getFee(address(ethToken), address(restakingToken))
            );
        }
        
        if(address(zircuitRestakeProxy) != address(0)){
            restakingToken.approve(address(zircuitRestakeProxy), restakingToken.balanceOf(address(this)));
            zircuitRestakeProxy.depositFor(address(restakingToken), address(this), restakingToken.balanceOf(address(this)));
        }
    }

    function withdrawFromRestakingProxy(
        uint256 ethAmount
    ) external override {
        uint256 stakingTokenAmount = swapProxy.getAmountInMaximum(address(restakingToken), address(ethToken), ethAmount);
        
        if(address(zircuitRestakeProxy) != address(0)){
            zircuitRestakeProxy.withdraw(address(restakingToken), stakingTokenAmount);
        }

        if(address(kelpRestakeProxy) != address(0) && address(kelpWithdrawRestakingPool) != address(0)) {
            restakingToken.approve(address(swapProxy), stakingTokenAmount);
            kelpWithdrawRestakingPool.withdraw(address(restakingToken), stakingTokenAmount);
        }else{
            restakingToken.approve(address(swapProxy), stakingTokenAmount);
            swapProxy.swapToWithOutput(
                address(this),
                address(restakingToken),
                ethAmount,
                address(ethToken),
                getFee(address(restakingToken), address(ethToken))
            );
        }
    }
}
