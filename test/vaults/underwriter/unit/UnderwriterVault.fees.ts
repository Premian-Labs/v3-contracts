import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  caller,
  receiver,
  setupBeforeTokenTransfer,
  token,
  vault,
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
import { ethers } from 'ethers';

export const testsFeeVars = [
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
    timeOfDepositReceiverAfter: 3000000000 + ONE_DAY,
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
    timeOfDepositReceiverAfter: 3000000000 + ONE_YEAR,
  },
];

describe('UnderwriterVault.fees', () => {
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
            it(`timeOfDeposit of receiver should equal ${test.timeOfDepositReceiverAfter}`, async () => {
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
