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
    IERC20 private ethToken;

    constructor(
        address _addressContractKelpRestake,
        address _addressContractZircuit,
        UniSwap _swapProxy,
        IERC20 _restakingToken
    ) {
        baseKelpRenzoProxyInit(
            msg.sender,
            _addressContractKelpRestake,
            _addressContractZircuit,
            _swapProxy,
            _restakingToken
        );
    }

    function depositToRestakingProxy(
        string memory refId
    ) external payable override {
        require(msg.value > 0, "INVALID_AMOUNT_ETH");
        // ethereum
        kelpRestakeProxy.depositETH{value: msg.value}(0, refId);
    }

    function withdrawFromRestakingProxy(uint256 ethAmount) external override {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        uint256 stakingTokenAmount = swapProxy.getAmountInMaximum(
            address(restakingToken),
            address(ethToken),
            ethAmount
        );

        if (address(zircuitRestakeProxy) != address(0)) {
            zircuitRestakeProxy.withdraw(
                address(restakingToken),
                stakingTokenAmount
            );
        }

        if (
            address(kelpRestakeProxy) != address(0) &&
            address(kelpWithdrawRestakingPool) != address(0)
        ) {
            restakingToken.approve(address(swapProxy), stakingTokenAmount);
            kelpWithdrawRestakingPool.withdraw(
                address(restakingToken),
                stakingTokenAmount
            );
        } else {
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

    function depositForZircuit() external override {
        restakingToken.approve(
            address(zircuitRestakeProxy),
            restakingToken.balanceOf(address(this))
        );
        zircuitRestakeProxy.depositFor(
            address(restakingToken),
            address(this),
            restakingToken.balanceOf(address(this))
        );
    }

    function updateNewAdmin(address _adminNew) external {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        updateAdmin(_adminNew);
    }
}
