// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../../../../interfaces/IZircuitRestakeProxy.sol";
import "../../../../extensions/Uniswap/Uniswap.sol";
import "../../../../interfaces/IWithdrawRestakingPool.sol";

abstract contract BaseKelpRenzoProxy is ReentrancyGuard {
    IZircuitRestakeProxy internal zircuitRestakeProxy;
    UniSwap internal swapProxy;
    IERC20 internal restakingToken;
    IWithdrawRestakingPool internal kelpWithdrawRestakingPool;

    function baseKelpRenzoProxyInit(address _addressContractZircuit, UniSwap _swapProxy, IERC20 _restakingToken) internal virtual {
        zircuitRestakeProxy = IZircuitRestakeProxy(_addressContractZircuit);
        swapProxy = _swapProxy;
        restakingToken = _restakingToken;
    }

    function updateKelpWithdrawRestaking (address _kelpWithdrawRestakingPoolAddress) external nonReentrant {
        kelpWithdrawRestakingPool = IWithdrawRestakingPool(_kelpWithdrawRestakingPoolAddress);
    }

    function updateZirCuitRestakeProxy (address _addressContractZircuit) external nonReentrant {
        zircuitRestakeProxy = IZircuitRestakeProxy(_addressContractZircuit);
    }

    function depositToRestakingProxy(uint256 ethAmount, string memory refId) external virtual nonReentrant {}

    function withdrawFromRestakingProxy(uint256 ethAmount) external virtual nonReentrant {}
}