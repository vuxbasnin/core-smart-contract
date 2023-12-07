import { ethers, network } from "hardhat";
import { expect } from "chai";
import { BigNumberish, ContractTransaction, Signer } from "ethers";
import * as Contracts from "../typechain-types"; // Adjust the path as necessary

interface MockERC20 extends Contracts.IERC20 {
  mint: (account: string, amount: BigNumberish) => Promise<ContractTransaction>;
}

describe("OnyxVault on Mainnet Fork", function () {
  let owner: Signer, user1: Signer, user2: Signer;
  let onyxVault: Contracts.StableCoinStrategy;
  let usdcAddress;
  let mockUSDC: MockERC20;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    // Deploy a mock USDC contract and mint tokens
    const MockUSDC = await ethers.getContractFactory("MockERC20");
    mockUSDC = (await MockUSDC.deploy()) as MockERC20;
    usdcAddress = await mockUSDC.getAddress();
    console.log("Deployed mUSDC at address %s", usdcAddress);

    // Mint USDC tokens to user1
    await mockUSDC.mint(await user1.getAddress(), ethers.parseEther("10000"));
    await mockUSDC.mint(await user2.getAddress(), ethers.parseEther("10000"));

    // Deploy your OnyxVault contract (adjust with correct types and constructor arguments)
    onyxVault = await ethers.deployContract("StableCoinStrategy", [
      usdcAddress,
      ethers.parseEther("4000000"),
    ]);
    console.log(
      "Deployed Onyx Vault to address %s",
      await onyxVault.getAddress()
    );
  });

  // it("should allow deposit of USDC", async function () {
  //   // Simulate USDC transfer to user1 for testing

  //   // console.log("1000 ETH = %s", ethers.parseEther("1000"));
  //   // await network.provider.send("hardhat_setBalance", [
  //   //   await user1.getAddress(),
  //   //   "0x3635c9adc5dea00000",
  //   // ]);

  //   // User1 approves OnyxVault to spend their USDC
  //   const depositAmount = ethers.parseEther("500.1"); // 500 USDC
  //   console.log(
  //     "User1 approving OnyxVault to spend %d USDC...",
  //     ethers.formatEther(depositAmount)
  //   );
  //   const usdc = await mockUSDC.connect(user1);
  //   await usdc.approve(await onyxVault.getAddress(), depositAmount);

  //   console.log("User1 depositing USDC into the OnyxVault...");
  //   // User1 deposits USDC into the OnyxVault
  //   await onyxVault.connect(user1).deposit(depositAmount);

  //   console.log("Checking user balance after deposit...");
  //   // Assertions
  //   const userBalance = await onyxVault.balanceOf(await user1.getAddress());
  //   console.log("User balance is:", ethers.formatEther(userBalance));
  //   expect(userBalance).to.equal(depositAmount);
  // });

  it("should handle deposits correctly", async function () {
    console.log("Testing deposit functionality...");

    // User1 approves OnyxVault to spend their USDC
    const depositAmount1 = ethers.parseEther("500"); // 500 USDC
    console.log(
      "User1 approving OnyxVault to spend %s USDC...",
      ethers.formatEther(depositAmount1)
    );
    await mockUSDC
      .connect(user1)
      .approve(await onyxVault.getAddress(), depositAmount1);

    // User1 deposits USDC into the OnyxVault
    console.log(
      "User1 depositing %s USDC into the OnyxVault...",
      ethers.formatEther(depositAmount1)
    );
    await onyxVault.connect(user1).deposit(depositAmount1);

    // check price per share
    const pricePerShare = await onyxVault.pricePerShare();
    const totalSupply = await onyxVault.totalSupply();
    const totalBalance = await onyxVault.totalBalance();
    console.log(
      "Price/Share %s, totalSupply= %s, totalBalance=%s",
      ethers.formatEther(pricePerShare.toString()),
      ethers.formatEther(totalSupply),
      ethers.formatEther(totalBalance)
    );

    // User1 approves OnyxVault to spend their USDC
    const depositAmount2 = ethers.parseEther("1000"); // 500 USDC
    console.log(
      "User2 approving OnyxVault to spend %s USDC...",
      ethers.formatEther(depositAmount2)
    );
    await mockUSDC
      .connect(user2)
      .approve(await onyxVault.getAddress(), depositAmount2);

    // User1 deposits USDC into the OnyxVault
    console.log(
      "User2 depositing %s USDC into the OnyxVault...",
      ethers.formatEther(depositAmount2)
    );
    await onyxVault.connect(user2).deposit(depositAmount2);

    // check price per share
    const pricePerShare2 = await onyxVault.pricePerShare();
    const totalSupply2 = await onyxVault.totalSupply();
    const totalBalance2 = await onyxVault.totalBalance();
    console.log(
      "Price/Share %s, totalSupply= %s, totalBalance=%s",
      ethers.formatEther(pricePerShare2.toString()),
      ethers.formatEther(totalSupply2),
      ethers.formatEther(totalBalance2)
    );

    // Assertions
    const user1Address = user1.getAddress();
    const user2Address = user2.getAddress();
    const totalSupplyAfter = await onyxVault.totalSupply();
    const totalBalanceAfter = await onyxVault.totalBalance();
    const user1BalanceAfter = await onyxVault.balanceOf(user1Address);
    const user2BalanceAfter = await onyxVault.balanceOf(user2Address);

    expect(totalSupplyAfter).to.equal(ethers.parseEther("1500"));
    expect(totalBalanceAfter).to.equal(ethers.parseEther("1500"));
    expect(user1BalanceAfter).to.equal(ethers.parseEther("500"));
    expect(user2BalanceAfter).to.equal(ethers.parseEther("1000"));
  });
});
