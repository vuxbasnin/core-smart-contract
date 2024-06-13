// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IERC721Receiver.sol";
import "../../extensions/RockOnyxAccessControl.sol";
import "./structs/RockOnyxStructs.sol";
import "./strategies/RockOnyxEthLiquidityStrategy.sol";
import "./strategies/RockOnyxOptionsStrategy.sol";
import "./strategies/RockOynxUsdLiquidityStrategy.sol";
import "hardhat/console.sol";

contract BaseRockOnyxOptionWheelVault is
    IERC721Receiver,
    RockOnyxAccessControl,
    RockOnyxEthLiquidityStrategy,
    RockOnyxOptionStrategy,
    RockOynxUsdLiquidityStrategy
{
    uint256 currentRound;
    mapping(address => DepositReceipt) internal depositReceipts;
    mapping(address => Withdrawal) internal withdrawals;
    mapping(uint256 => uint256) internal roundWithdrawalShares;
    mapping(uint256 => uint256) internal roundPricePerShares;
    VaultParams internal vaultParams;
    VaultState internal vaultState;
    AllocateRatio internal allocateRatio;

    // migration
    DepositReceiptArr[] depositReceiptArr;
    WithdrawalArr[] withdrawalArr;
    // end migration

    function onERC721Received(
        address operator,
        address from,
        uint tokenId,
        bytes calldata
    ) external returns (bytes4) {}

    function emergencyShutdown(
        address receiver,
        address tokenAddress,
        uint256 amount
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        IERC20(tokenAddress).transfer(receiver, amount);
    }

    // migration
    function updateDepositArr(DepositReceipt memory depositReceipt) internal {
        for (uint256 i = 0; i < depositReceiptArr.length; i++) {
            if (depositReceiptArr[i].owner == msg.sender) {
                depositReceiptArr[i].depositReceipt = depositReceipt;
                return;
            }
        }

        depositReceiptArr.push(DepositReceiptArr(msg.sender, depositReceipt));
    }

    function updateWithdrawalArr(Withdrawal memory withdrawal) internal {
        for (uint256 i = 0; i < withdrawalArr.length; i++) {
            if (withdrawalArr[i].owner == msg.sender) {
                withdrawalArr[i].withdrawal = withdrawal;
                return;
            }
        }

        withdrawalArr.push(WithdrawalArr(msg.sender, withdrawal));
    }

    function exportVaultState()
        external
        view
        returns (
            uint256,
            uint256[] memory,
            uint256[] memory,
            DepositReceiptArr[] memory,
            WithdrawalArr[] memory,
            VaultParams memory,
            VaultState memory,
            AllocateRatio memory,
            EthLPState memory,
            UsdLPState memory,
            OptionsStrategyState memory
        )
    {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        uint256[] memory exportRoundWithdrawalShares = new uint256[](currentRound);
        uint256[] memory exportRoundPricePerShares = new uint256[](currentRound);
        for (uint256 i = 0; i < currentRound; i++) {
            exportRoundWithdrawalShares[i] = roundWithdrawalShares[i];
            exportRoundPricePerShares[i] = roundPricePerShares[i];
        }

        return (
            currentRound,
            exportRoundWithdrawalShares,
            exportRoundPricePerShares,
            depositReceiptArr,
            withdrawalArr,
            vaultParams,
            vaultState,
            allocateRatio,
            ethLPState,
            usdLPState,
            optionsState
        );
    }

    function importVaultState(
        uint256 _currentRound,
        uint256[] calldata _roundWithdrawalShares,
        uint256[] calldata _roundPricePerShares,
        DepositReceiptArr[] calldata _depositReceiptArr,
        WithdrawalArr[] calldata _withdrawalArr,
        VaultParams calldata _vaultParams,
        VaultState calldata _vaultState,
        AllocateRatio calldata _allocateRatio,
        EthLPState calldata _ethLPState,
        UsdLPState calldata _usdLPState,
        OptionsStrategyState calldata _optionsState
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        for (uint256 i = 0; i < _currentRound; i++) {
            roundWithdrawalShares[i] = _roundWithdrawalShares[i];
            roundPricePerShares[i] = _roundPricePerShares[i];
        }
        depositReceiptArr = _depositReceiptArr;
        for (uint256 i = 0; i < _depositReceiptArr.length; i++) {
            depositReceipts[_depositReceiptArr[i].owner] = _depositReceiptArr[i]
                .depositReceipt;
        }
        withdrawalArr = _withdrawalArr;
        for (uint256 i = 0; i < _withdrawalArr.length; i++) {
            withdrawals[_withdrawalArr[i].owner] = _withdrawalArr[i].withdrawal;
        }
        currentRound = _currentRound;
        vaultParams = _vaultParams;
        vaultState = _vaultState;
        allocateRatio = _allocateRatio;
        ethLPState = _ethLPState;
        usdLPState = _usdLPState;
        optionsState = _optionsState;
    }
    // end migration
}
