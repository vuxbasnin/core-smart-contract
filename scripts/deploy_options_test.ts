import { ethers, network } from "hardhat";

import {
  CHAINID,
  USDC_ADDRESS,
  AEVO_ADDRESS,
  AEVO_CONNECTOR_ADDRESS,
  USDCE_ADDRESS,
  AEVO_TRADER_ADDRESS,
} from "../constants";

const chainId: CHAINID = network.config.chainId ?? 0;

const aevoAddress = AEVO_ADDRESS[chainId] ?? "";
const aevoConnectorAddress = AEVO_CONNECTOR_ADDRESS[chainId] ?? "";
const aevoReceiver = AEVO_TRADER_ADDRESS[chainId] ?? "";
const usdcAddress = USDC_ADDRESS[chainId] ?? "";
const usdceAddress = USDCE_ADDRESS[chainId] ?? "";

const cap = ethers.parseUnits("1000000", 18); // Cap is 1,000,000 with 18 decimals

async function deployAevoOptions(): Promise<string> {
  const AevoOptions = await ethers.getContractFactory("AevoOptions");
  const aevoOptions = await AevoOptions.deploy(
    usdceAddress,
    aevoAddress,
    aevoConnectorAddress
  );

  await aevoOptions.waitForDeployment();
  const aevoOptionsAddress = await aevoOptions.getAddress();
  console.log(`AevoOptions deployed to: ${aevoOptionsAddress}`);

  return aevoOptionsAddress;
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy AevoOptions and set optionsVendorProxy
  const optionsVendorProxy = await deployAevoOptions();

  // Deploy OptionsTestVault
  const OptionsTestVault = await ethers.getContractFactory("OptionsTestVault");
  const optionsTestVault = await OptionsTestVault.deploy(
    usdceAddress,
    optionsVendorProxy,
    aevoReceiver,
    usdceAddress,
    cap,
    { gasLimit: 3000000 }
  );

  await optionsTestVault.waitForDeployment();
  const optionsTestVaultAddress = await optionsTestVault.getAddress();
  console.log(`OptionsTestVault deployed to: ${optionsTestVaultAddress}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
