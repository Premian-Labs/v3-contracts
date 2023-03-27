import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import {
  addMockDeposit,
  feeReceiver,
  increaseTotalAssets,
  increaseTotalShares,
  vaultSetup,
} from '../VaultSetup';
import {
  formatEther,
  formatUnits,
  parseEther,
  parseUnits,
} from 'ethers/lib/utils';
import { expect } from 'chai';
import {
  getValidMaturity,
  increaseTo,
  latest,
  ONE_DAY,
  ONE_HOUR,
  ONE_WEEK,
} from '../../../../utils/time';
import {
  ERC20Mock,
  IPoolMock,
  UnderwriterVaultMock,
} from '../../../../typechain';
import { BigNumber, ethers } from 'ethers';
import { setMaturities } from '../VaultSetup';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { MockContract } from '@ethereum-waffle/mock-contract';
import { PoolUtil } from '../../../../utils/PoolUtil';
import { PoolKey, TokenType } from '../../../../utils/sdk/types';
import exp from 'constants';
import { start } from 'repl';
import { Sign } from 'crypto';
import { put } from 'axios';

let startTime: number;
let vault: UnderwriterVaultMock;
let token: ERC20Mock;

describe('UnderwriterVault.fees', () => {
  describe('#_chargeManagementFees', () => {
    startTime = 10000000;
    const tests = [
      {
        totalAssets: 11.2,
        lastFeeEventTimestamp: startTime - ONE_DAY,
        timestamp: startTime + ONE_DAY,
        protocolFees: 1,
        managementFeeRate: 0.01,
        protocolFeesAfter: 1 + (11.2 * 0.01 * 2) / 365,
      },
      {
        totalAssets: 1.2,
        lastFeeEventTimestamp: startTime - ONE_DAY,
        timestamp: startTime + ONE_DAY,
        protocolFees: 0.0123,
        managementFeeRate: 0.0,
        protocolFeesAfter: 0.0123,
      },
      {
        totalAssets: 501.3,
        lastFeeEventTimestamp: startTime - ONE_DAY,
        timestamp: startTime + 6 * ONE_HOUR,
        protocolFees: 0.0123,
        managementFeeRate: 0.05,
        protocolFeesAfter: 0.0123 + (501.3 * 0.05 * (1 + 1 / 4)) / 365,
      },
    ];

    async function setupManagementFees(isCall: boolean, test: any) {
      let { callVault, putVault, base, quote } = await loadFixture(vaultSetup);
      vault = isCall ? callVault : putVault;
      token = isCall ? base : quote;
      await vault.setProtocolFees(parseEther(test.protocolFees.toString()));
      await vault.setLastFeeEventTimestamp(test.lastFeeEventTimestamp);
      await vault.setManagementFeeRate(
        parseEther(test.managementFeeRate.toString()),
      );
      await vault.chargeManagementFees(
        test.timestamp,
        parseEther(test.totalAssets.toString()),
      );
      return vault;
    }
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        tests.forEach(async (test) => {
          describe('', () => {
            it(`protocol fees after charging equals ${test.protocolFeesAfter}`, async () => {
              vault = await setupManagementFees(isCall, test);
              const protocolFees = parseFloat(
                formatEther(await vault.getProtocolFees()),
              );
              const delta = 1e-16;
              expect(protocolFees).to.be.closeTo(test.protocolFeesAfter, delta);
            });
            it(`lastFeeEventTimestamp equals ${test.timestamp}`, async () => {
              vault = await setupManagementFees(isCall, test);
              expect(await vault.getLastFeeEventTimestamp()).to.eq(
                test.timestamp,
              );
            });
          });
        });
      });
    }
  });

  describe('#chargeFees', () => {});

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

    // set pps and shares user
    const userShares = parseEther(test.shares.toString());
    await vault.mintMock(caller.address, userShares);
    const userDeposit = parseEther((test.shares * test.ppsUser).toFixed(12));
    await vault.setNetUserDeposit(caller.address, userDeposit);
    //const ppsUser = parseEther(test.ppsUser.toString());
    //const ppsAvg = await vault.getAveragePricePerShare(caller.address);
    //expect(ppsAvg).to.eq(ppsUser);
    expect(await vault.totalSupply()).to.eq(totalSupply);
    expect(await vault.getPricePerShare()).to.eq(pps);
    //expect(await vault.getAveragePricePerShare(caller.address)).to.eq(pps);

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
    return { vault, caller, token };
  }

  describe('#_maxTransferableShares', () => {
    const tests = [
      {
        shares: 1.1,
        pps: 1.0,
        ppsUser: 1,
        totalSupply: 2.2,
        maxTransferable: 1.1,
        performanceFeeRate: 0.01,
      },
      {
        shares: 0.0,
        pps: 1.3,
        ppsUser: 1.3,
        totalSupply: 2.2,
        maxTransferable: 0.0,
        performanceFeeRate: 0.01,
      },
      {
        shares: 2.3,
        pps: 1.5,
        ppsUser: 1.2,
        totalSupply: 2.5,
        maxTransferable: 2.27125,
        performanceFeeRate: 0.05,
      },
    ];
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        tests.forEach(async (test) => {
          it(`userShares ${test.shares}, ppsUser ${test.ppsUser}, ppsVault ${test.pps}, then maxTransferableShares equals ${test.maxTransferable}`, async () => {
            const { vault, caller } = await setupMaxTransferable(isCall, test);
            const maxTransferable = await vault.maxTransferableShares(
              caller.address,
            );
            expect(parseFloat(formatEther(maxTransferable))).to.eq(
              test.maxTransferable,
            );
          });
        });
      });
    }
  });

  let caller: SignerWithAddress;
  let receiver: SignerWithAddress;
  let token: ERC20Mock;

  async function setupBeforeTokenTransfer(isCall: boolean, test: any) {
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
    // if we dont ad this amount the pps will be lower due to collected fees
    if (false) {
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
    }
    // set pps and shares user caller
    const userShares = parseEther(test.shares.toString());
    await vault.mintMock(caller.address, userShares);
    const userDeposit = parseEther((test.shares * test.ppsUser).toFixed(12));
    await vault.setNetUserDeposit(caller.address, userDeposit);

    // check pps is as expected
    const ppsUser = parseEther(test.ppsUser.toString());
    const ppsAvg = await vault.getAveragePricePerShare(caller.address);
    expect(ppsAvg).to.eq(ppsUser);

    expect(await vault.totalSupply()).to.eq(totalSupply);
    expect(await vault.getPricePerShare()).to.eq(pps);

    await vault.setPerformanceFeeRate(
      parseEther(test.performanceFeeRate.toString()),
    );
    return { vault, caller, receiver };
  }

  describe('#_beforeTokenTransfer', () => {
    const tests = [
      {
        shares: 1.1,
        pps: 1.0,
        ppsUser: 1.0,
        totalSupply: 2.2,
        performanceFeeRate: 0.01,
        protocolFeesInitial: 0.1,
        protocolFees: 0.1,
        transferAmount: 0.1,
        sharesAfter: 1.1,
        netUserDepositReceiver: 1.2,
        netUserDepositReceiverAfter: 1.3,
        netUserDepositCallerAfter: 1.0,
      },
      {
        shares: 2.3,
        pps: 1.5,
        ppsUser: 1.2,
        totalSupply: 2.5,
        performanceFeeRate: 0.05,
        protocolFeesInitial: 0.1,
        protocolFees: 0.1230625,
        transferAmount: 1.23,
        sharesAfter: 2.284625,
        netUserDepositReceiver: 1.2,
        netUserDepositReceiverAfter: 3.045,
        netUserDepositCallerAfter: 1.26555,
      },
    ];

    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        tests.forEach(async (test) => {
          describe('', () => {
            it(`the balanceOf caller equals ${test.sharesAfter}`, async () => {
              let { vault, caller, receiver } = await setupBeforeTokenTransfer(
                isCall,
                test,
              );

              await vault.beforeTokenTransfer(
                caller.address,
                receiver.address,
                parseEther(test.transferAmount.toString()),
              );

              const balanceAfter = parseFloat(
                formatEther(await vault.balanceOf(caller.address)),
              );
              expect(balanceAfter).to.eq(test.sharesAfter);
            });
            it(`protocolFees should equal ${test.protocolFees}`, async () => {
              const feesAfter = parseFloat(
                formatEther(await vault.getProtocolFees()),
              );
              expect(feesAfter).to.eq(test.protocolFees);
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
              const delta = 1e-8;
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
          let test = tests[1];
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
          let test = tests[1];
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
          let test = tests[1];
          let { vault, caller, receiver } = await setupBeforeTokenTransfer(
            isCall,
            test,
          );
          await expect(
            vault.beforeTokenTransfer(
              caller.address,
              receiver.address,
              parseEther((2.27126).toString()),
            ),
          ).to.be.revertedWithCustomError(
            vault,
            'ERC20Base__TransferExceedsBalance',
          );
          // check that this passes
          await vault.beforeTokenTransfer(
            caller.address,
            receiver.address,
            parseEther((2.27125).toString()),
          );
        });

        it('if receiver address is the vault address the netUserDeposit should not be updated', async () => {
          let test = tests[1];
          let { vault, caller } = await setupBeforeTokenTransfer(isCall, test);

          await vault.beforeTokenTransfer(
            caller.address,
            vault.address,
            parseEther(test.transferAmount.toString()),
          );

          const netUserDepositReceiver = parseFloat(
            formatEther(await vault.getNetUserDeposit(vault.address)),
          );
          expect(netUserDepositReceiver).to.eq(0);

          const netUserDepositCaller = parseFloat(
            formatEther(await vault.getNetUserDeposit(caller.address)),
          );
          expect(netUserDepositCaller).to.eq(test.netUserDepositCallerAfter);
        });
      });
    }
  });

  describe('#_performanceFeeVars', () => {
    const tests = [
      {
        shares: 1.1,
        pps: 1.0,
        ppsUser: 1.0,
        assets: 0.1,
        balanceShares: 1.1,
        totalSupply: 2.2,
        performanceFeeRate: 0.01,
        transferAmount: 0.1,
        performance: 1.0,
        feeInShares: 0,
        feeInAssets: 0,
      },
      {
        shares: 2.3,
        pps: 1.5,
        ppsUser: 1.2,
        assets: 1.845,
        balanceShares: 2.3,
        totalSupply: 2.5,
        performanceFeeRate: 0.05,
        transferAmount: 1.23,
        performance: 1.25,
        feeInShares: 0.015375,
        feeInAssets: 0.0230625,
      },
    ];

    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        tests.forEach(async (test) => {
          describe('', () => {
            it('', async () => {
              let { vault, caller, receiver } = await setupBeforeTokenTransfer(
                isCall,
                test,
              );
              const {
                pps,
                ppsAvg,
                shares,
                assets,
                balanceShares,
                performance,
                feeInShares,
                feeInAssets,
              } = await vault.getPerformanceFeeVars(
                caller.address,
                parseEther(test.transferAmount.toString()),
              );
              await expect(pps).to.eq(parseEther(test.pps.toString()));
              await expect(ppsAvg).to.eq(parseEther(test.ppsUser.toString()));
              await expect(shares).to.eq(
                parseEther(test.transferAmount.toString()),
              );
              await expect(assets).to.eq(parseEther(test.assets.toString()));
              await expect(balanceShares).to.eq(
                parseEther(test.balanceShares.toString()),
              );
              await expect(performance).to.eq(
                parseEther(test.performance.toString()),
              );
              await expect(feeInShares).to.eq(
                parseEther(test.feeInShares.toString()),
              );
              await expect(feeInAssets).to.eq(
                parseEther(test.feeInAssets.toString()),
              );
            });
          });
        });
      });
    }
  });

  describe('#maxWithdraw', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('maxWithdraw should revert for a zero address', async () => {
          const { callVault, base, quote } = await loadFixture(vaultSetup);
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
      const { callVault, receiver } = await loadFixture(vaultSetup);
      await expect(
        callVault.afterDeposit(
          receiver.address,
          parseEther('0'),
          parseEther('1'),
        ),
      ).to.be.revertedWithCustomError(callVault, 'Vault__ZeroAsset');
    });
    it('_afterDeposit should revert for zero share amount', async () => {
      const { callVault, receiver } = await loadFixture(vaultSetup);
      await expect(
        callVault.afterDeposit(
          receiver.address,
          parseEther('1'),
          parseEther('0'),
        ),
      ).to.be.revertedWithCustomError(callVault, 'Vault__ZeroShares');
    });

    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('_afterDeposit should increment netUserDeposits by the scaled asset amount', async () => {
          const { callVault, putVault, receiver, base, quote } =
            await loadFixture(vaultSetup);
          vault = isCall ? callVault : putVault;
          token = isCall ? base : quote;
          await vault.setNetUserDeposit(receiver.address, parseEther('1.5'));
          await vault.afterDeposit(
            receiver.address,
            parseUnits('3', await token.decimals()),
            parseEther('2'),
          );
          expect(await vault.getNetUserDeposit(receiver.address)).to.eq(
            parseEther('4.5'),
          );
        });
      });
    }
  });
});
