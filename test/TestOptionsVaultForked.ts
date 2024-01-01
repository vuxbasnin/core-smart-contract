import { ethers } from "hardhat";
import { expect, use } from "chai";
import * as Contracts from "../typechain-types";
import { BaseContract, Signer } from "ethers";

describe("OptionsTestVault Contract", function () {
  let optionsTestVault: Contracts.OptionsTestVault;
  let aevoOptionsProxy: Contracts.AevoOptions;
  let deployer: Signer;
  let user: Signer;
  let bridgedUsdc: Contracts.IERC20;
  const aevoAddress = "0x80d40e32FAD8bE8da5C6A42B8aF1E181984D137c";
  const aevoConnectorAddress = "0x69Adf49285c25d9f840c577A0e3cb134caF944D3";
  let optionsReceiver: string;
  const cap = ethers.parseUnits("1000000", 18);

  const assetAddress = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"; // Bridged USDC's address

  async function deployAevoOptions(): Promise<string> {
    const AevoOptions = await ethers.getContractFactory("AevoOptions");
    aevoOptionsProxy = await AevoOptions.deploy(
      assetAddress,
      aevoAddress,
      aevoConnectorAddress
    );

    await aevoOptionsProxy.waitForDeployment();
    const aevoOptionsAddress = await aevoOptionsProxy.getAddress();
    console.log(`AevoOptions deployed to: ${aevoOptionsAddress}`);

    return aevoOptionsAddress;
  }

  before(async function () {
    // Get signers
    [deployer, user] = await ethers.getSigners();
    console.log("User = %s", await user.getAddress());

    console.log(
      "Deploying contracts with the account:",
      await deployer.getAddress()
    );

    // Deploy AevoOptions and set optionsVendorProxy
    const optionsVendorProxy = await deployAevoOptions();

    optionsReceiver = await user.getAddress();

    // Deploy OptionsTestVault
    const OptionsTestVault = await ethers.getContractFactory(
      "OptionsTestVault"
    );
    optionsTestVault = await OptionsTestVault.deploy(
      assetAddress,
      optionsVendorProxy,
      optionsReceiver,
      assetAddress,
      cap
    );

    const optionsTestVaultAddress = await optionsTestVault.getAddress();
    console.log(`OptionsTestVault deployed to: ${optionsTestVaultAddress}`);

    const impersonatedSigner = await ethers.getImpersonatedSigner(
      "0x226bf1ee0bb0cf647f6a9f0d8b380d6ab56de3cb"
    );
    console.log("address 1", await impersonatedSigner.getAddress());

    // await aevoOptionsProxy
    //   .connect(user)
    //   .topUpGasFees({ value: ethers.parseEther("100") });

    // await optionsTestVault
    //   .connect(user)
    //   .topUpGasFees({ value: ethers.parseEther("100") });

    // console.log(
    //   "Balance eth of aevoOptionsProxy %s",
    //   await ethers.provider.getBalance(optionsVendorProxy)
    // );

    // Connect to the asset contract (assuming ERC20)
    bridgedUsdc = await ethers.getContractAt("IERC20", assetAddress);
    console.log(
      "balance of 1",
      await bridgedUsdc
        .connect(impersonatedSigner)
        .balanceOf(await impersonatedSigner.getAddress())
    );

    const transferTx = await bridgedUsdc
      .connect(impersonatedSigner)
      .transfer(optionsReceiver, ethers.parseUnits("1000", 6)); // Transferring 1000 USDC
    await transferTx.wait();

    const balanceOfUser = await bridgedUsdc
      .connect(user)
      .balanceOf(optionsReceiver);
    console.log("Balance of user %s", balanceOfUser);
  });

  it.skip("should deposit tokens to the OptionsTestVault", async function () {
    // First, approve the OptionsTestVault contract to spend tokens
    const depositAmount = ethers.parseUnits("1000", 6);
    await bridgedUsdc
      .connect(user)
      .approve(await optionsTestVault.getAddress(), depositAmount);

    // Then, deposit tokens to the OptionsTestVault
    await optionsTestVault.connect(user).deposit(depositAmount);

    console.log("Deposited to optionsTestVault");

    // Then, deposit tokens to the OptionsTestVault
    await optionsTestVault.connect(deployer).depositToVendor(depositAmount, {
      value: ethers.parseEther("0.001753"),
    });

    console.log(
      "eth Balance eth of deployer %s",
      await ethers.provider.getBalance(deployer)
    );

    const pricePerShare = await optionsTestVault.pricePerShare();
    const totalSupply = await optionsTestVault.totalSupply();
    const totalBalance = await optionsTestVault.totalBalance();
    console.log(
      "Price/Share %s, totalSupply= %s, totalBalance=%s",
      ethers.formatEther(pricePerShare.toString()),
      ethers.formatEther(totalSupply),
      ethers.formatEther(totalBalance)
    );
  });
});
