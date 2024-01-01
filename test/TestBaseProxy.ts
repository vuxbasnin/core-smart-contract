import { expect } from "chai";
import { ethers } from "hardhat";
import * as Contracts from "../typechain-types";
import { Signer } from "ethers";
import { transferIERC20FundForUser } from "./TestHelper";

describe("BaseProxy", function () {
  let baseProxy: Contracts.BaseProxy;
  let usdc: Contracts.IERC20;
  let owner: Signer, user: Signer;

  const usdcAddress = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";

  beforeEach(async function () {
    // Deploy BaseProxy
    const BaseProxy = await ethers.getContractFactory("BaseProxy");
    baseProxy = await BaseProxy.deploy();

    // Get signers
    [owner, user] = await ethers.getSigners();
    usdc = await ethers.getContractAt("IERC20", usdcAddress);

    await transferIERC20FundForUser(
      usdc,
      "0x1f7bc4da1a0c2e49d7ef542f74cd46a3fe592cb1",
      user,
      5000
    );

    // Send USDC to BaseProxy
    await usdc
      .connect(user)
      .transfer(await baseProxy.getAddress(), ethers.parseUnits("100", 6));
  });

  it("should allow admin to withdraw USDC", async function () {
    // Initial balance check
    const userAddress = await user.getAddress();
    const initialBalance = await usdc.balanceOf(userAddress);

    // Withdraw USDC
    await baseProxy
      .connect(owner)
      .withdraw(
        userAddress,
        usdcAddress,
        ethers.parseUnits("100", 6)
      );

    // Final balance check
    const finalBalance = await usdc.balanceOf(userAddress);
    expect(finalBalance - initialBalance).to.equal(
      ethers.parseUnits("100", 6)
    );
  });

});
