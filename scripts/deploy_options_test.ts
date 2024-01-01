import { ethers } from "hardhat";
const aevoAddress = "0x80d40e32FAD8bE8da5C6A42B8aF1E181984D137c";
const usdceAddress = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
const aevoReceiver = "0x1A8dC40895883B270564939bD9922EBfeE8857e4";
const aevoConnectorAddress = "0x69Adf49285c25d9f840c577A0e3cb134caF944D3";
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
