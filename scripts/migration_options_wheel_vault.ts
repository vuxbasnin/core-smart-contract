const { ethers, network } = require("hardhat");
import axios from "axios";

import * as Contracts from "../typechain-types";
import {
  CHAINID
} from "../constants";

const chainId: CHAINID = network.config.chainId;
const privateKey = process.env.PRIVATE_KEY || "";

let rockOnyxOptionWheelVaultContract: Contracts.RockOnyxUSDTVault;
let newRockOnyxOptionWheelVaultContract: Contracts.RockOnyxUSDTVault;

async function main() {
    console.log('-------------migration option wheel---------------');
    const admin = new ethers.Wallet(privateKey, ethers.provider);
    const vaultAddress = "0x077835528875C27bFaCBc5d923C919BC56a9C250";
    rockOnyxOptionWheelVaultContract = await ethers.getContractAt("RockOnyxUSDTVault", vaultAddress);
    
    const newVaultAddress = "0xDc7BCA217d22A221A67580611253f16412AF063D";
    newRockOnyxOptionWheelVaultContract = await ethers.getContractAt("RockOnyxUSDTVault", newVaultAddress);

    console.log("-------------export old vault state---------------");
    let exportVaultStateTx = await rockOnyxOptionWheelVaultContract
      .connect(admin)
      .exportVaultState();
    
    console.log(exportVaultStateTx);
    console.log(exportVaultStateTx[3][0][1]);
    console.log(exportVaultStateTx[3][1][1]);
    console.log(exportVaultStateTx[3][2][1]);

    console.log("-------------import vault state---------------");
    const _currentRound = exportVaultStateTx[0];
    const _roundWithdrawalShares = [...exportVaultStateTx[1]];
    const _roundPricePerShares = [...exportVaultStateTx[2]];
    const _depositReceiptArr = exportVaultStateTx[3].map((element) => {
        return {
          owner: element[0],
          depositReceipt: {
            shares: element[1][0],
            depositAmount: element[1][1],
          },
        };
    });
    const _withdrawalArr = exportVaultStateTx[4].map((element) => {
        return {
          owner: element[0],
          withdrawal: {
            shares: element[1][0],
            round: element[1][1],
          },
        };
    });
    const _vaultParams = {
        decimals: exportVaultStateTx[5][0],
        asset: exportVaultStateTx[5][1],
        minimumSupply: exportVaultStateTx[5][2],
        cap: exportVaultStateTx[5][3],
        performanceFeeRate: exportVaultStateTx[5][4],
        managementFeeRate: exportVaultStateTx[5][5],
    };
    const _vaultState = {
        performanceFeeAmount: exportVaultStateTx[6][0],
        managementFeeAmount: exportVaultStateTx[6][1],
        currentRoundFeeAmount: exportVaultStateTx[6][2],
        withdrawPoolAmount: exportVaultStateTx[6][3],
        pendingDepositAmount: exportVaultStateTx[6][4],
        totalShares: exportVaultStateTx[6][5],
        lastLockedAmount: exportVaultStateTx[6][6],
    };
    const _allocateRatio = {
        ethLPRatio: exportVaultStateTx[7][0],
        usdLPRatio: exportVaultStateTx[7][1],
        optionsRatio: exportVaultStateTx[7][2],
        decimals: exportVaultStateTx[7][3],
    };
    const _ethLPState = {
        tokenId: exportVaultStateTx[8][0],
        liquidity: exportVaultStateTx[8][1],
        lowerTick: exportVaultStateTx[8][2],
        upperTick: exportVaultStateTx[8][3],
        unAllocatedBalance: exportVaultStateTx[8][4],
    };
    const _usdLPState = {
        tokenId: exportVaultStateTx[9][0],
        liquidity: exportVaultStateTx[9][1],
        lowerTick: exportVaultStateTx[9][2],
        upperTick: exportVaultStateTx[9][3],
        unAllocatedUsdcBalance: exportVaultStateTx[9][4],
        unAllocatedUsdceBalance: exportVaultStateTx[9][5],
    };
    const _optiondsState = {
        allocatedUsdcBalance: exportVaultStateTx[10][0],
        unAllocatedUsdcBalance: exportVaultStateTx[10][1],
        unsettledProfit: exportVaultStateTx[10][2],
        unsettledLoss: exportVaultStateTx[10][3],
    };

    const importVaultStateTx = await newRockOnyxOptionWheelVaultContract
      .connect(admin)
      .importVaultState(
          _currentRound,
          _roundWithdrawalShares,
          _roundPricePerShares,
          _depositReceiptArr,
          _withdrawalArr,
          _vaultParams,
          _vaultState,
          _allocateRatio,
          _ethLPState,
          _usdLPState,
          _optiondsState
      );
    
    console.log("-------------export new vault state---------------");
    exportVaultStateTx = await newRockOnyxOptionWheelVaultContract
      .connect(admin)
      .exportVaultState();
    
    console.log(exportVaultStateTx);
    console.log(exportVaultStateTx[3][0][1]);
    console.log(exportVaultStateTx[3][1][1]);
    console.log(exportVaultStateTx[3][2][1]);
  }
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  