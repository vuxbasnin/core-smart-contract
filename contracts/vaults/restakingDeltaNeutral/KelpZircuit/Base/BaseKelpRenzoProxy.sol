// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../../../../interfaces/IZircuitRestakeProxy.sol";
import "../../../../extensions/Uniswap/Uniswap.sol";
import "../../../../interfaces/IWithdrawRestakingPool.sol";
import "../../../../interfaces/IKelpRestakeProxy.sol";
import "../../../../extensions/RockOnyxAccessControl.sol";

abstract contract BaseKelpRenzoProxy is ReentrancyGuard, RockOnyxAccessControl {
    IZircuitRestakeProxy internal zircuitRestakeProxy;
    IKelpRestakeProxy internal kelpRestakeProxy;
    UniSwap internal swapProxy;
    IERC20 internal restakingToken;
    IWithdrawRestakingPool internal kelpWithdrawRestakingPool;
    address internal admin;

    function baseKelpRenzoProxyInit(address _admin, address _addressContractKelpRestake, address _addressContractZircuit, UniSwap _swapProxy, IERC20 _restakingToken) internal virtual {
        zircuitRestakeProxy = IZircuitRestakeProxy(_addressContractZircuit);
        kelpRestakeProxy = IKelpRestakeProxy(_addressContractKelpRestake);
        swapProxy = _swapProxy;
        restakingToken = _restakingToken;
        admin = _admin;
        _grantRole(ROCK_ONYX_ADMIN_ROLE, _admin);
    }

    function updateKelpWithdrawRestaking (address _kelpWithdrawRestakingPoolAddress) external nonReentrant {
        kelpWithdrawRestakingPool = IWithdrawRestakingPool(_kelpWithdrawRestakingPoolAddress);
    }

    function updateZirCuitRestakeProxy (address _addressContractZircuit) external nonReentrant {
        zircuitRestakeProxy = IZircuitRestakeProxy(_addressContractZircuit);
    }

    function depositToRestakingProxy(string memory refId) external virtual payable nonReentrant {}

    function withdrawFromRestakingProxy(uint256 ethAmount) external virtual nonReentrant {}

    function depositForZircuit() external virtual nonReentrant {}

    function updateAdmin(address _adminNew) internal nonReentrant {
        admin = _adminNew;
    }
}