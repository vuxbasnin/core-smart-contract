const { ethers, network } = require("hardhat");
import axios from "axios";

import * as Contracts from "../typechain-types";
import {
  CHAINID,
  ARB_ADDRESS} from "../constants";

const chainId: CHAINID = network.config.chainId;
const privateKey = process.env.PRIVATE_KEY || "";
// const chainId: CHAINID = 42161;

let rockOnyxUSDTVaultContract: Contracts.RockOnyxUSDTVault;
let arb: Contracts.IERC20;

async function main() {
    console.log('-------------claim reward on Camelot---------------');
    const arbAddress = ARB_ADDRESS[chainId];
    arb = await ethers.getContractAt("IERC20", arbAddress);
    // const contractAdmin = await ethers.getImpersonatedSigner("0x20f89bA1B0Fc1e83f9aEf0a134095Cd63F7e8CC7");
    const contractAdmin = new ethers.Wallet(privateKey, ethers.provider);
    const vaultAddress = "0x18994527E6FfE7e91F1873eCA53e900CE0D0f276";
    rockOnyxUSDTVaultContract = await ethers.getContractAt("RockOnyxUSDTVault", vaultAddress);

    interface TransactionData {
      [token: string]: {
        proof?: any; // Define the type for proof
        claim: any; // Define the type for claim
      };
    }

    let transactionData : TransactionData;
    try {
      const { data } = await axios.get(
        `https://api.angle.money/v2/merkl?chainIds[]=42161&user=${vaultAddress}`,
        {
          timeout: 50000,
        }
      );
      
      transactionData  = data[chainId].transactionData;
    } catch (error) {
      throw new Error("Angle API not responding");
    }
    const tokens = Object.keys(transactionData).filter(
      (k) => transactionData[k].proof !== undefined
    );
    const claims = tokens.map((t) => transactionData[t].claim);
    const proofs = tokens.map((t) => transactionData[t].proof);  
    const users = tokens.map((t) => vaultAddress);

    console.log(tokens);
    console.log(claims);
    console.log(proofs);
    console.log(await arb.balanceOf(vaultAddress));

    // const claimlTx = await rockOnyxUSDTVaultContract
    //   .connect(contractAdmin)
    //   .claimReward(users, tokens, claims, proofs as string[][]);
    // await claimlTx.wait();

    // console.log(await arb.balanceOf(vaultAddress));
  }

  // We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  