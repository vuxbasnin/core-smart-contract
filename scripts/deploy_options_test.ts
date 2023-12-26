import { ethers } from "hardhat";

const aevoAddress = "0xFB73dFff0AE6AA94559b1B17421CF42E198B8D22";
const assetAddress = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
const optionsReceiver = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
const cap = ethers.parseUnits("1000000", 18); // Cap is 1,000,000 with 18 decimals

async function deployAevoOptions(): Promise<string> {
  const AevoOptions = await ethers.getContractFactory("AevoOptions");
  const aevoOptions = await AevoOptions.deploy(aevoAddress);

  await aevoOptions.waitForDeployment();
  const aevoOptionsAddress = await aevoOptions.getAddress();
  console.log(`AevoOptions deployed to: ${aevoOptionsAddress}`);

  return aevoOptionsAddress;
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy AevoOptions and set optionsVendorProxy
  // const optionsVendorProxy = await deployAevoOptions();

  // Deploy OptionsTestVault
  const OptionsTestVault = await ethers.getContractFactory("OptionsTestVault");
  const optionsTestVault = await OptionsTestVault.deploy(
    assetAddress,
    "0x76aF5aFE79B0f29da885c9c5BFeb73F79dfC2A11",
    optionsReceiver,
    cap
  );

  await optionsTestVault.waitForDeployment();
  const optionsTestVaultAddress = await optionsTestVault.getAddress();
  console.log(`OptionsTestVault deployed to: ${optionsTestVaultAddress}`);

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
