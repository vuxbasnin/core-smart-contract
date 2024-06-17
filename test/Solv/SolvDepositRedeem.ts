const { ethers } = require("hardhat");
import { expect } from "chai";
import * as Contracts from "../../typechain-types";
import {
    CHAINID,
    SOLV_ADDRESS_YIELD_FARM,
    WBTC_ADDRESS
} from "../../constants";
import { network } from "hardhat";
import { Signer } from "ethers";

const chainId: CHAINID = network.config.chainId as CHAINID;
console.log("chainId: ", chainId);

describe("Solv deposit and redeem", () => {
    let admin: Signer;
    let WBTC: Contracts.IERC20;

    let addressSolvYFAbritrum = SOLV_ADDRESS_YIELD_FARM[chainId];
    let wbtcAddress = WBTC_ADDRESS[chainId];

    async function depositToSolv() {
        const factory = await ethers.getContractFactory("Solv");
        console.log('addressSolvYFAbritrum ', addressSolvYFAbritrum);
        console.log('wbtcAddress ', wbtcAddress);
        
    }
})