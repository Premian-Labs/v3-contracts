import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import {
  addMockDeposit,
  increaseTotalAssets,
  increaseTotalShares,
  setMaturities,
  vaultSetup,
} from '../UnderwriterVault.fixture';
import { formatEther, parseEther, parseUnits } from 'ethers/lib/utils';
import { expect } from 'chai';
import {
  increaseTo,
  ONE_DAY,
  ONE_WEEK,
  ONE_YEAR,
} from '../../../../utils/time';
import { ERC20Mock, UnderwriterVaultMock } from '../../../../typechain';
import { ethers } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

let vault: UnderwriterVaultMock;

describe('UnderwriterVault.fees', () => {
  describe('#_claimFees', () => {
    async function setup(isCall: boolean, test: any) {
      let { callVault, putVault, feeReceiver, base, quote } = await loadFixture(
        vaultSetup,
      );
      vault = isCall ? callVault : putVault;
      const token = isCall ? base : quote;
      await vault.setProtocolFees(parseEther(test.protocolFees.toString()));
      await increaseTotalAssets(vault, test.protocolFees, base, quote);
      await token.mint(
        feeReceiver.address,
        parseUnits(
          test.balanceOfFeeReceiver.toString(),
          await token.decimals(),
        ),
      );
      await vault.claimFees();
      return { vault, feeReceiver, token };
    }
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it(`protocolFees should be transferred to fee receiver address`, async () => {
          const test = { protocolFees: 0.123, balanceOfFeeReceiver: 10.1 };
          const { token, feeReceiver } = await setup(isCall, test);
          expect(await token.balanceOf(feeReceiver.address)).to.eq(
            parseUnits('10.223', await token.decimals()),
          );
        });
      });
    }
  });

  async function setup(isCall: boolean, test: any) {
    let { callVault, putVault, base, quote, caller } = await loadFixture(
      vaultSetup,
    );

    vault = isCall ? callVault : putVault;
    token = isCall ? base : quote;
    const decimals = await token.decimals();

    // set pps and totalSupply vault
    const totalSupply = parseEther(test.totalSupply.toString());
    await increaseTotalShares(
      vault,
      parseFloat((test.totalSupply - test.shares).toFixed(12)),
    );
    const pps = parseEther(test.pps.toString());
    const vaultDeposit = parseUnits(
      (test.pps * test.totalSupply).toFixed(12),
      decimals,
    );
    await token.mint(vault.address, vaultDeposit);
    await vault.increaseTotalAssets(
      parseEther((test.pps * test.totalSupply).toFixed(12)),
    );

    // set pps and shares user
    const userShares = parseEther(test.shares.toString());
    await vault.mintMock(caller.address, userShares);
    const userDeposit = parseEther((test.shares * test.ppsUser).toFixed(12));
    await vault.setNetUserDeposit(caller.address, userDeposit);
    const ppsUser = parseEther(test.ppsUser.toString());
    const ppsAvg = await vault.getAveragePricePerShare(caller.address);

    expect(ppsAvg).to.eq(ppsUser);

    expect(await vault.totalSupply()).to.eq(totalSupply);
    expect(await vault.getPricePerShare()).to.eq(pps);

    return { vault, caller, token };
  }

  describe('#_getAveragePricePerShare', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        const tests = [
          {
            shares: 1.1,
            totalSupply: 2.2,
            pps: 1.0,
            ppsUser: 1,
          },
          {
            shares: 2.3,
            totalSupply: 2.5,
            pps: 1.5,
            ppsUser: 1.2,
          },
        ];

        tests.forEach(async (test) => {
          it(`userShares ${test.shares}, userDeposit ${
            test.ppsUser * test.shares
          }, ppsVault ${test.pps}, then ppsUser equals ${
            test.pps
          }`, async () => {
            const { vault, caller } = await setup(isCall, test);
            const ppsUser = parseFloat(
              formatEther(await vault.getAveragePricePerShare(caller.address)),
            );
            expect(ppsUser).to.eq(test.ppsUser);
          });
        });
      });
    }
  });

  async function setupMaxTransferable(isCall: boolean, test: any) {
    let { vault, caller, token } = await setup(isCall, test);
    await vault.setPerformanceFeeRate(
      parseEther(test.performanceFeeRate.toString()),
    );
    await vault.setManagementFeeRate(
      parseEther(test.managementFeeRate.toString()),
    );
    return { vault, caller, token };
  }

  let caller: SignerWithAddress;
  let receiver: SignerWithAddress;
  let token: ERC20Mock;

  async function setupGetFeeVars(isCall: boolean, test: any) {
    let {
      callVault,
      putVault,
      base,
      quote,
      caller: _caller,
      receiver: _receiver,
    } = await loadFixture(vaultSetup);

    vault = isCall ? callVault : putVault;
    token = isCall ? base : quote;
    caller = _caller;
    receiver = _receiver;

    // set pps and totalSupply vault
    const totalSupply = parseEther(test.totalSupply.toString());
    await increaseTotalShares(
      vault,
      parseFloat((test.totalSupply - test.shares).toFixed(12)),
    );
    const pps = parseEther(test.pps.toString());
    const vaultDeposit = parseUnits(
      (test.pps * test.totalSupply).toFixed(12),
      await token.decimals(),
    );
    await token.mint(vault.address, vaultDeposit);

    await vault.increaseTotalAssets(
      parseEther((test.pps * test.totalSupply).toFixed(12)),
    );

    // set pps and shares user caller
    const userShares = parseEther(test.shares.toString());
    await vault.mintMock(caller.address, userShares);
    const userDeposit = parseEther((test.shares * test.ppsUser).toFixed(12));
    await vault.setNetUserDeposit(caller.address, userDeposit);
    await vault.setTimeOfDeposit(caller.address, test.timeOfDeposit);

    // check pps is as expected
    const ppsUser = parseEther(test.ppsUser.toString());
    if (test.shares > 0) {
      const ppsAvg = await vault.getAveragePricePerShare(caller.address);
      expect(ppsAvg).to.eq(ppsUser);
    }

    expect(await vault.totalSupply()).to.eq(totalSupply);
    expect(await vault.getPricePerShare()).to.eq(pps);

    await vault.setPerformanceFeeRate(
      parseEther(test.performanceFeeRate.toString()),
    );
    await vault.setManagementFeeRate(
      parseEther(test.managementFeeRate.toString()),
    );
    return { vault, caller, receiver };
  }

  async function setupBeforeTokenTransfer(isCall: boolean, test: any) {
    let { vault, caller, receiver } = await setupGetFeeVars(isCall, test);

    await token.mint(
      vault.address,
      parseUnits(test.protocolFeesInitial.toString(), await token.decimals()),
    );
    await vault.setProtocolFees(
      parseEther(test.protocolFeesInitial.toString()),
    );
    await vault.setNetUserDeposit(
      receiver.address,
      parseEther(test.netUserDepositReceiver.toString()),
    );

    return { vault, caller, receiver };
  }

  const testsFeeVars = [
    {
      shares: 1.1,
      pps: 1.0,
      ppsUser: 1.0,
      assets: 0.1,
      balanceShares: 1.1,
      totalSupply: 2.2,
      performanceFeeRate: 0.01,
      managementFeeRate: 0.02,
      transferAmount: 0.1,
      performance: 1.0,
      performanceFeeInShares: 0,
      performanceFeeInAssets: 0,
      managementFeeInShares: 0.000005479452054794,
      managementFeeInAssets: 0.000005479452054794,
      totalFeeInShares: 0.000005479452054794,
      totalFeeInAssets: 0.000005479452054794,
      timeOfDeposit: 3000000000,
      timestamp: 3000000000 + ONE_DAY,
      maxTransferableShares: 1.0999397260273973,
      // beforeTokenTransfer
      protocolFeesInitial: 0.1,
      protocolFees: 0.1 + 0.000005479452054794,
      sharesAfter: 1.0999945204845256,
      netUserDepositReceiver: 1.2,
      netUserDepositReceiverAfter: 1.3,
      netUserDepositCallerAfter: 0.9999945205, // 1,1 * 1,0 * ((1,1 - 0,1 - 0,000005479452054794) / 1,1)
    },
    {
      shares: 2.3,
      pps: 1.5,
      ppsUser: 1.2,
      assets: 1.845,
      balanceShares: 2.3,
      totalSupply: 2.5,
      performanceFeeRate: 0.05,
      managementFeeRate: 0.02,
      transferAmount: 1.23,
      performance: 1.25,
      performanceFeeInShares: 0.015375,
      performanceFeeInAssets: 0.0230625,
      managementFeeInShares: 0.0246,
      managementFeeInAssets: 0.0369,
      totalFeeInShares: 0.039975,
      totalFeeInAssets: 0.0599625,
      timeOfDeposit: 3000000000,
      timestamp: 3000000000 + ONE_YEAR,
      maxTransferableShares: 2.22525,
      // beforeTokenTransfer
      protocolFeesInitial: 0.1,
      protocolFees: 0.1 + 0.0599625,
      sharesAfter: 2.260025,
      netUserDepositReceiver: 1.2,
      netUserDepositReceiverAfter: 3.045,
      netUserDepositCallerAfter: 1.23603, // 2,3 * 1,2 * ((2,3 - 1,23 - 0,039975) / 2,3)
    },
  ];

  describe('#_updateTimeOfDeposit', () => {
    async function setup(test: any) {
      let { callVault: vault, caller } = await loadFixture(vaultSetup);
      await vault.mintMock(
        caller.address,
        parseEther(test.sharesInitial.toString()),
      );
      if (test.timeOfDeposit > 0)
        await vault.setTimeOfDeposit(caller.address, test.timeOfDeposit);

      return { vault, caller };
    }
    const tests = [
      {
        sharesInitial: 0,
        shareAmount: 1,
        timeOfDeposit: 0,
        timestamp: 300000,
        timeOfDepositNew: 300000,
        message:
          'should update the time of deposit to be the timestamp of first deposit',
      },
      {
        sharesInitial: 2,
        shareAmount: 3,
        timeOfDeposit: 300000,
        timestamp: 300000 + ONE_DAY,
        timeOfDepositNew: 351840,
        message:
          'should update the time of deposit to be the weighted average based on shares',
      },
    ];

    tests.forEach(async (test) => {
      it(test.message, async () => {
        let { vault, caller } = await setup(test);

        await vault.setTimestamp(test.timestamp);

        await vault.updateTimeOfDeposit(
          caller.address,
          parseEther(test.sharesInitial.toString()),
          parseEther(test.shareAmount.toString()),
        );
        const timeOfDepositUpdated = parseInt(
          (await vault.getTimeOfDeposit(caller.address)).toString(),
        );
        expect(timeOfDepositUpdated).to.eq(test.timeOfDepositNew);
      });
    });
  });

  describe('#_getFeeInternal', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        testsFeeVars.forEach(async (test) => {
          it('should compute the correct internal fee variables for the user with shares=${test.sharesInitial}', async () => {
            let { vault, caller } = await setupGetFeeVars(isCall, test);

            await vault.setTimestamp(test.timestamp);

            const pricePerShare = await vault.getPricePerShare();

            const {
              assets,
              balanceShares,
              performanceFeeInAssets,
              managementFeeInAssets,
              totalFeeInShares,
              totalFeeInAssets,
            } = await vault.getFeeInternal(
              caller.address,
              parseEther(test.transferAmount.toString()),
              pricePerShare,
            );
            await expect(assets).to.eq(parseEther(test.assets.toString()));
            await expect(balanceShares).to.eq(
              parseEther(test.balanceShares.toString()),
            );
            await expect(performanceFeeInAssets).to.eq(
              parseEther(test.performanceFeeInAssets.toString()),
            );
            await expect(managementFeeInAssets).to.eq(
              parseEther(test.managementFeeInAssets.toString()),
            );
            await expect(totalFeeInShares).to.eq(
              parseEther(test.totalFeeInShares.toString()),
            );
            await expect(totalFeeInAssets).to.eq(
              parseEther(test.totalFeeInAssets.toString()),
            );
          });
        });
      });
    }
  });

  describe('#_maxTransferableShares', () => {
    let test: any = {
      shares: 0.0,
      pps: 1.0,
      ppsUser: 1.0,
      assets: 0.1,
      balanceShares: 1.1,
      totalSupply: 2.2,
      performanceFeeRate: 0.01,
      managementFeeRate: 0.02,
      transferAmount: 0.1,
      performance: 1.0,
      performanceFeeInShares: 0.0,
      performanceFeeInAssets: 0.0,
      managementFeeInShares: 0.0,
      managementFeeInAssets: 0.0,
      totalFeeInShares: 0.0,
      totalFeeInAssets: 0.0,
      timeOfDeposit: 3000000000,
      timestamp: 3000000000 + ONE_DAY,
      maxTransferableShares: 0.0,
    };

    const myClonedArray: any = [];
    testsFeeVars.forEach((val) => myClonedArray.push(Object.assign({}, val)));
    myClonedArray.push(test);
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        myClonedArray.forEach(async (test) => {
          it(`userShares ${test.shares}, ppsUser ${test.ppsUser}, ppsVault ${test.pps}, then maxTransferableShares equals ${test.maxTransferableShares}`, async () => {
            const { vault, caller } = await setupGetFeeVars(isCall, test);
            await vault.setTimestamp(test.timestamp);

            const feeVars = await vault.getFeeInternal(
              caller.address,
              parseEther(test.shares.toString()),
              parseEther(test.pps.toString()),
            );

            const maxTransferableShares = await vault.maxTransferableShares(
              feeVars,
            );

            expect(parseFloat(formatEther(maxTransferableShares))).to.eq(
              test.maxTransferableShares,
            );
          });
        });
      });
    }
  });

  describe('#_beforeTokenTransfer', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        testsFeeVars.forEach(async (test) => {
          describe('', () => {
            it(`the balanceOf caller equals ${test.sharesAfter}`, async () => {
              let { vault, caller, receiver } = await setupBeforeTokenTransfer(
                isCall,
                test,
              );
              await increaseTo(test.timestamp);
              await vault.beforeTokenTransfer(
                caller.address,
                receiver.address,
                parseEther(test.transferAmount.toString()),
              );

              const balanceAfter = parseFloat(
                formatEther(await vault.balanceOf(caller.address)),
              );
              const delta = 1e-7;
              expect(balanceAfter).to.be.closeTo(test.sharesAfter, delta);
            });
            it(`protocolFees should equal ${test.protocolFees}`, async () => {
              const feesAfter = parseFloat(
                formatEther(await vault.getProtocolFees()),
              );
              const delta = 1e-7;
              expect(feesAfter).to.be.closeTo(test.protocolFees, delta);
            });
            it('vault pps should stay constant', async () => {
              const pps = parseFloat(
                formatEther(await vault.getPricePerShare()),
              );
              expect(pps).to.eq(test.pps);
            });
            it(`netUserDeposit of caller should equal ${test.netUserDepositCallerAfter}`, async () => {
              const netUserDeposit = parseFloat(
                formatEther(await vault.getNetUserDeposit(caller.address)),
              );
              const delta = 1e-5;
              expect(netUserDeposit).to.be.closeTo(
                test.netUserDepositCallerAfter,
                delta,
              );
            });
            it(`netUserDeposit of receiver should equal ${test.netUserDepositReceiverAfter}`, async () => {
              const netUserDeposit = parseFloat(
                formatEther(await vault.getNetUserDeposit(receiver.address)),
              );
              const delta = 1e-8;
              expect(netUserDeposit).to.be.closeTo(
                test.netUserDepositReceiverAfter,
                delta,
              );
            });
          });
        });
        it('no effect if address from is zero address', async () => {
          let test = testsFeeVars[1];
          let { vault, receiver } = await setupBeforeTokenTransfer(
            isCall,
            test,
          );
          const callerAddress = ethers.constants.AddressZero;
          await vault.beforeTokenTransfer(
            callerAddress,
            receiver.address,
            parseEther(test.transferAmount.toString()),
          );
          const netUserDepositCaller = parseFloat(
            formatEther(await vault.getNetUserDeposit(callerAddress)),
          );
          expect(netUserDepositCaller).to.eq(0);

          const netUserDepositReceiver = parseFloat(
            formatEther(await vault.getNetUserDeposit(receiver.address)),
          );
          expect(netUserDepositReceiver).to.eq(test.netUserDepositReceiver);
        });

        it('no effect if address to is zero address', async () => {
          let test = testsFeeVars[1];
          let { vault, caller } = await setupBeforeTokenTransfer(isCall, test);
          const receiverAddress = ethers.constants.AddressZero;

          await vault.beforeTokenTransfer(
            caller.address,
            receiverAddress,
            parseEther(test.transferAmount.toString()),
          );

          const netUserDepositReceiver = parseFloat(
            formatEther(await vault.getNetUserDeposit(receiverAddress)),
          );
          expect(netUserDepositReceiver).to.eq(0);

          const netUserDepositCaller = parseFloat(
            formatEther(await vault.getNetUserDeposit(caller.address)),
          );
          expect(netUserDepositCaller).to.eq(2.76);
        });

        it('revert if transfer amount is too high', async () => {
          let test = testsFeeVars[1];
          let { vault, caller, receiver } = await setupBeforeTokenTransfer(
            isCall,
            test,
          );
          await increaseTo(test.timestamp);
          await expect(
            vault.beforeTokenTransfer(
              caller.address,
              receiver.address,
              parseEther((test.maxTransferableShares + 0.01).toString()),
            ),
          ).to.be.revertedWithCustomError(
            vault,
            'Vault__TransferExceedsBalance',
          );
          // check that this passes
          await vault.beforeTokenTransfer(
            caller.address,
            receiver.address,
            parseEther((test.maxTransferableShares - 0.01).toString()),
          );
        });

        it('if receiver address is the vault address the netUserDeposit should not be updated', async () => {
          let test = testsFeeVars[1];
          let { vault, caller } = await setupBeforeTokenTransfer(isCall, test);

          await increaseTo(test.timestamp);
          await vault.beforeTokenTransfer(
            caller.address,
            vault.address,
            parseEther(test.transferAmount.toString()),
          );

          const netUserDepositReceiver = parseFloat(
            formatEther(await vault.getNetUserDeposit(vault.address)),
          );
          expect(netUserDepositReceiver).to.eq(0);

          const netUserDepositCallerAfter = parseFloat(
            formatEther(await vault.getNetUserDeposit(caller.address)),
          );
          const delta = 1e-7;
          expect(netUserDepositCallerAfter).to.be.closeTo(
            test.netUserDepositCallerAfter,
            delta,
          );
        });
      });
    }
  });

  describe('#maxWithdraw', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('maxWithdraw should revert for a zero address', async () => {
          const { callVault, base, quote, lp } = await loadFixture(vaultSetup);
          await setMaturities(callVault);
          await addMockDeposit(callVault, 2, base, quote);
          await expect(
            callVault.maxWithdraw(ethers.constants.AddressZero),
          ).to.be.revertedWithCustomError(callVault, 'Vault__AddressZero');
        });

        let test = {
          shares: 2.3,
          pps: 1.5,
          ppsUser: 1.2,
          totalSupply: 2.5,
          maxTransferable: 2.27125,
          managementFeeRate: 0.0,
          performanceFeeRate: 0.05,
        };

        it('should return max transferable assets of the caller', async () => {
          // assets caller: 2.3 * 1.5
          // tax caller: 2.3 * 1.5 * 0.05 * 0.25 = 0.43125
          // maxWithdrawable = assets - tax = 3.406875
          const { vault, caller } = await setupMaxTransferable(isCall, test);
          const assetAmount = await vault.maxWithdraw(caller.address);
          const decimals = await token.decimals();
          expect(assetAmount).to.eq(parseUnits('3.406875', decimals));
        });

        it('should return available assets', async () => {
          // maxWithdrawable = assets - tax = 3.406875
          // available = assets - locked = 3.75 - 1.2 = 2.55
          const { vault, caller } = await setupMaxTransferable(isCall, test);
          await setMaturities(vault);
          await vault.increaseTotalLockedAssets(parseEther('1.2'));
          const assetAmount = await vault.maxWithdraw(caller.address);
          const decimals = await token.decimals();
          expect(assetAmount).to.eq(parseUnits('2.55', decimals));
        });
      });
    }
  });

  describe('#maxRedeem', () => {
    it('maxRedeem should revert for a zero address', async () => {
      const { callVault, receiver, base, quote } = await loadFixture(
        vaultSetup,
      );
      await setMaturities(callVault);
      await addMockDeposit(callVault, 2, base, quote, 2, receiver.address);
      await expect(
        callVault.maxRedeem(ethers.constants.AddressZero),
      ).to.be.revertedWithCustomError(callVault, 'Vault__AddressZero');
    });

    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        let test = {
          shares: 2.3,
          pps: 1.5,
          ppsUser: 1.2,
          totalSupply: 2.5,
          managementFeeRate: 0.0,
          performanceFeeRate: 0.05,
        };

        it('should return max transferable assets of the caller', async () => {
          // assets caller: 2.3 * 1.5
          // tax caller: 2.3 * 1.5 * 0.05 * 0.25 = 0.43125
          // maxWithdrawable = assets - tax = 3.406875
          const { vault, caller } = await setupMaxTransferable(isCall, test);
          const assetAmount = await vault.maxRedeem(caller.address);
          expect(assetAmount).to.eq(parseEther('2.27125'));
        });

        it('should return available assets', async () => {
          // maxWithdrawable = assets - tax = 3.406875
          // available = assets - locked = 3.75 - 1.2 = 2.55
          const { vault, caller } = await setupMaxTransferable(isCall, test);
          await setMaturities(vault);
          await vault.increaseTotalLockedAssets(parseEther('1.2'));
          const assetAmount = await vault.maxRedeem(caller.address);
          expect(assetAmount).to.eq(parseEther('1.7'));
        });
      });
    }
  });

  describe('#_afterDeposit', () => {
    it('_afterDeposit should revert for a zero address', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      await expect(
        callVault.afterDeposit(
          ethers.constants.AddressZero,
          parseEther('1'),
          parseEther('1'),
        ),
      ).to.be.revertedWithCustomError(callVault, 'Vault__AddressZero');
    });
    it('_afterDeposit should revert for zero asset amount', async () => {
      const { callVault, caller } = await loadFixture(vaultSetup);
      await expect(
        callVault.afterDeposit(
          caller.address,
          parseEther('0'),
          parseEther('1'),
        ),
      ).to.be.revertedWithCustomError(callVault, 'Vault__ZeroAsset');
    });
    it('_afterDeposit should revert for zero share amount', async () => {
      const { callVault, caller } = await loadFixture(vaultSetup);
      await expect(
        callVault.afterDeposit(
          caller.address,
          parseEther('1'),
          parseEther('0'),
        ),
      ).to.be.revertedWithCustomError(callVault, 'Vault__ZeroShares');
    });

    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('_afterDeposit should increment netUserDeposits by the scaled asset amount', async () => {
          const { callVault, putVault, caller, base, quote } =
            await loadFixture(vaultSetup);
          vault = isCall ? callVault : putVault;
          token = isCall ? base : quote;
          // mock the current user deposits
          const timestamp = 1000000;
          await vault.setTimestamp(timestamp);
          const initialAssets = parseEther('2.5');
          const initialShares = parseEther('1.5');
          await vault.mintMock(caller.address, initialShares);
          await vault.setNetUserDeposit(caller.address, initialAssets);
          await vault.setTimeOfDeposit(caller.address, timestamp);
          await vault.setTotalAssets(initialAssets);
          // increment time and call afterDeposit
          const newlyDepositedAssets = parseUnits('3', await token.decimals());
          const newlyMintedShares = parseEther('2');
          await vault.mintMock(caller.address, newlyMintedShares);
          await vault.setTimestamp(timestamp + ONE_WEEK);
          await vault.afterDeposit(
            caller.address,
            newlyDepositedAssets,
            newlyMintedShares,
          );
          expect(await vault.totalAssets()).to.eq(
            parseUnits('5.5', await token.decimals()),
          );
          expect(await vault.getNetUserDeposit(caller.address)).to.eq(
            parseEther('5.5'),
          );
          // (1.5 * t_0 + 2 * t_1) / 3.5 = (1,5 * 1000000 + 2 * 1604800) / 3,5
          const newTimeOfDeposit = parseInt(
            (await vault.getTimeOfDeposit(caller.address)).toString(),
          );
          expect(newTimeOfDeposit).to.eq(1345600);
        });
      });
    }
  });

  describe('#_beforeWithdraw', () => {
    it('_beforeWithdraw should revert for a zero address', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      await expect(
        callVault.beforeWithdraw(
          ethers.constants.AddressZero,
          parseEther('1'),
          parseEther('1'),
        ),
      ).to.be.revertedWithCustomError(callVault, 'Vault__AddressZero');
    });
    it('_beforeWithdraw should revert for zero asset amount', async () => {
      const { callVault, caller } = await loadFixture(vaultSetup);
      await expect(
        callVault.beforeWithdraw(
          caller.address,
          parseEther('0'),
          parseEther('1'),
        ),
      ).to.be.revertedWithCustomError(callVault, 'Vault__ZeroAsset');
    });
    it('_beforeWithdraw should revert for zero share amount', async () => {
      const { callVault, caller } = await loadFixture(vaultSetup);
      await expect(
        callVault.beforeWithdraw(
          caller.address,
          parseEther('1'),
          parseEther('0'),
        ),
      ).to.be.revertedWithCustomError(callVault, 'Vault__ZeroShares');
    });

    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('test that _beforeWithdraw calls _beforeTokenTransfer to transfer performance related fees', async () => {
          // setup
          // netUserDeposit: 1.5, timeOfDeposit: 3000000000, initialShares: 1.5,
          // totalAssets: 3, pps: 2
          const { callVault, putVault, caller, base, quote } =
            await loadFixture(vaultSetup);

          vault = isCall ? callVault : putVault;
          token = isCall ? base : quote;

          // setup
          const timeOfDeposit = 3000000000;
          await vault.setManagementFeeRate(parseEther('0.02'));
          await vault.setPerformanceFeeRate(parseEther('0.05'));
          await vault.setNetUserDeposit(caller.address, parseEther('1.5'));
          await vault.setTimeOfDeposit(caller.address, timeOfDeposit);
          await vault.mintMock(caller.address, parseEther('1.5'));
          await vault.increaseTotalAssets(parseEther('3'));
          expect(await vault.getPricePerShare()).to.eq(parseEther('2'));

          await vault.setTimestamp(timeOfDeposit + 0.5 * ONE_YEAR);
          await vault.beforeWithdraw(
            caller.address,
            parseUnits('2.0', await token.decimals()), // assets that are going to be deducted
            parseEther('1.0'), // share amount
          );
          // performanceFeeInShares = return * fee * share amount = 100% * 0.05 * 1 = 0.05
          // managementFeeInShares = 0.02 * shareAmount * 1 / 2 = 0.01
          // totalFeeInShares = 0.06
          // factor = 1.5 * (1.5 - 1 - 0.06) / 1.5
          // totalFeeInAssets = 0.06 * 2 = 1.2
          // netUserDeposit should decrease proportionally to the shares redeemed + share fees
          expect(await vault.getNetUserDeposit(caller.address)).to.eq(
            parseEther('0.439999999999999999'),
          );
          // time of deposit should not change on a withdrawal
          const newTimeOfDeposit = parseInt(
            (await vault.getTimeOfDeposit(caller.address)).toString(),
          );
          expect(newTimeOfDeposit).to.eq(timeOfDeposit);
          // check that totalAssets was decreased by the asset amount withdrawn but also by the protocol fees in assets that were charged
          // totalAssets remaining 3 - 2 - 0.12 = 0.88
          expect(await vault.totalAssets()).to.eq(
            parseUnits('0.88', await token.decimals()),
          );
        });
      });
    }
  });
});
