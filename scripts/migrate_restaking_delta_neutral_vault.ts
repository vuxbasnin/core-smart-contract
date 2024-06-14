const { ethers, network } = require("hardhat");
import axios from "axios";

import * as Contracts from "../typechain-types";
import {
  CHAINID
} from "../constants";

const chainId: CHAINID = network.config.chainId;
const privateKey = process.env.PRIVATE_KEY || "";
const oldPrivateKey = process.env.OLD_PRIVATE_KEY || "";

async function main() {
    console.log('-------------migration contract---------------');
    
    const oldAdmin = new ethers.Wallet(oldPrivateKey, ethers.provider);
    console.log("old admin address %s", await oldAdmin.getAddress());

    const newAdmin = new ethers.Wallet(privateKey, ethers.provider);
    console.log("new admin address %s", await newAdmin.getAddress());

    const oldVaultAddress = "0x2B7cDAD36a86fd05Ac1680CDc42a0EA16804D80c";
    const oldContract = await ethers.getContractAt("KelpRestakingDeltaNeutralVault", oldVaultAddress);
    
    const newVaultAddress = "";
    const newContract = await ethers.getContractAt("KelpRestakingDeltaNeutralVault", newVaultAddress);

    console.log("-------------export old vault state---------------");
    let exportVaultStateTx = await oldContract
      .connect(oldAdmin)
      .exportVaultState();
  
    console.log(exportVaultStateTx);
    
    console.log("-------------import vault state---------------");
    const _depositReceiptArr = exportVaultStateTx[0].map((element: any[][]) => {
      return {
        owner: element[0],
        depositReceipt: {
          shares: element[1][0],
          depositAmount: element[1][1],
        },
      };
    });
    const _withdrawalArr = exportVaultStateTx[1].map((element: any[][]) => {
      return {
        owner: element[0],
        withdrawal: {
          shares: element[1][0],
          pps: element[1][1],
          profit: element[1][2],
          performanceFee: element[1][3],
          withdrawAmount: element[1][4],
        },
      };
    });
    const _vaultParams = {
      decimals: exportVaultStateTx[2][0],
      asset: exportVaultStateTx[2][1],
      minimumSupply: exportVaultStateTx[2][2],
      cap: exportVaultStateTx[2][3],
      performanceFeeRate: exportVaultStateTx[2][4],
      managementFeeRate: exportVaultStateTx[2][5],
      networkCost: exportVaultStateTx[2][6] == 0 ? 1e6 : exportVaultStateTx[2][6]
    };
    const _vaultState = {
      performanceFeeAmount: exportVaultStateTx[3][0],
      managementFeeAmount: exportVaultStateTx[3][1],
      withdrawPoolAmount: exportVaultStateTx[3][2],
      pendingDepositAmount: exportVaultStateTx[3][3],
      totalShares: exportVaultStateTx[3][4],
    };
    const _ethStakeLendState = {
      unAllocatedBalance: exportVaultStateTx[4][0],
      totalBalance: exportVaultStateTx[4][1],
    };
    const _perpDexState = {
      unAllocatedBalance: exportVaultStateTx[5][0],
      perpDexBalance: exportVaultStateTx[5][1],
    };

    const importVaultStateTx = await newContract
      .connect(newAdmin)
      .importVaultState(
        _depositReceiptArr,
        _withdrawalArr,
        _vaultParams,
        _vaultState,
        _ethStakeLendState,
        _perpDexState
      );
      
    console.log("-------------export new vault state---------------");
    exportVaultStateTx = await newContract
      .connect(newAdmin)
      .exportVaultState();
  
    console.log(exportVaultStateTx);
  }
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  