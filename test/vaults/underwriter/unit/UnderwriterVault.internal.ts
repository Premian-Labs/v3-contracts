import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import {
  addMockDeposit,
  createPool,
  increaseTotalAssets,
  vaultSetup,
} from '../VaultSetup';
import { formatEther, parseEther, parseUnits } from 'ethers/lib/utils';
import { expect } from 'chai';
import {
  getValidMaturity,
  increaseTo,
  latest,
  ONE_DAY,
  ONE_HOUR,
  ONE_WEEK,
} from '../../../../utils/time';
import { ERC20Mock, UnderwriterVaultMock } from '../../../../typechain';
import { BigNumber } from 'ethers';
import { setMaturities } from '../VaultSetup';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

let startTime: number;
let spot: number;
let minMaturity: number;
let maxMaturity: number;

let vault: UnderwriterVaultMock;

describe('UnderwriterVault', () => {
  describe('#_availableAssets', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        before(async () => {
          const { callVault, putVault, caller, receiver, base, quote } =
            await loadFixture(vaultSetup);
          vault = isCall ? callVault : putVault;
          await setMaturities(vault);
          await addMockDeposit(vault, 2, base, quote);
        });
        it('expected to equal totalAssets = 2', async () => {
          expect(await vault.getAvailableAssets()).to.eq(parseEther('2'));
        });
        it('expected to equal (totalAssets - totalLockedSpread) = 1.998', async () => {
          await vault.increaseTotalLockedSpread(parseEther('0.002'));
          expect(await vault.getAvailableAssets()).to.eq(parseEther('1.998'));
        });
        it('expected to equal (totalAssets - totalLockedSpread - totalLockedAssets) = 1.498', async () => {
          await vault.increaseTotalLockedAssets(parseEther('0.5'));
          expect(await vault.getAvailableAssets()).to.eq(parseEther('1.498'));
        });
        it('expected to equal (totalAssets - totalLockedSpread - totalLockedAssets) = 1.298', async () => {
          await vault.increaseTotalLockedSpread(parseEther('0.2'));
          expect(await vault.getAvailableAssets()).to.eq(parseEther('1.298'));
        });
        it('expected to equal (totalAssets - totalLockedSpread - totalLockedAssets) = 1.2979', async () => {
          await vault.increaseTotalLockedAssets(parseEther('0.0001'));
          expect(await vault.getAvailableAssets()).to.eq(parseEther('1.2979'));
        });
      });
    }
  });

  describe('#_afterBuy', () => {
    const premium = 0.5;
    const spread = 0.1;
    const size = 1;
    const strike = 100;
    let maturity: number;
    let totalAssets: number;
    let spreadUnlockingRate: number;
    let afterBuyTimestamp: number;

    async function setupAfterBuyVault(isCall: boolean) {
      // afterBuy function is independent of call / put option type
      const { callVault } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      await callVault.setIsCall(isCall);
      console.log('Setup vault.');

      maturity = minMaturity;
      spreadUnlockingRate = spread / (minMaturity - startTime);

      // await callVault.afterBuy(
      //   minMaturity,
      //   parseEther(premium.toString()),
      //   maturity - startTime,
      //   parseEther(size.toString()),
      //   parseEther(spread.toString()),
      //   parseEther(strike.toString()),
      // );
      afterBuyTimestamp = await latest();
      console.log('Processed afterBuy.');
      return { vault: callVault };
    }

    it('lastSpreadUnlockUpdate should equal the time we executed afterBuy as we updated the state there', async () => {
      const { vault } = await setupAfterBuyVault(true);
      expect(await vault.lastSpreadUnlockUpdate()).to.eq(afterBuyTimestamp);
    });

    it('spreadUnlockingRates should equal', async () => {
      expect(
        parseFloat(formatEther(await vault.spreadUnlockingRate())),
      ).to.be.closeTo(spreadUnlockingRate, 0.000000000000000001);
    });

    it('positionSize should equal ', async () => {
      const positionSize = await vault.positionSize(
        maturity,
        parseEther(strike.toString()),
      );
      expect(parseFloat(formatEther(positionSize))).to.eq(size);
    });

    it('spreadUnlockingRate / ticks', async () => {
      expect(
        parseFloat(formatEther(await vault.spreadUnlockingTicks(maturity))),
      ).to.be.closeTo(spreadUnlockingRate, 0.000000000000000001);
    });

    it('totalLockedSpread should equa', async () => {
      expect(parseFloat(formatEther(await vault.totalLockedSpread()))).to.eq(
        spread,
      );
    });

    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('totalLockedAssets should equal', async () => {
          const { vault } = await setupAfterBuyVault(isCall);
          const totalLocked = isCall ? size : size * strike;
          expect(
            parseFloat(formatEther(await vault.totalLockedAssets())),
          ).to.eq(totalLocked);
        });
      });
    }
  });

  describe('#_settleMaturity', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        let maturity: number;
        const size = parseEther('2');
        const strike1 = parseEther('1000');
        const strike2 = parseEther('2000');
        let totalLockedAssets: BigNumber;
        let newLockedAfterSettlement: BigNumber;
        let newTotalAssets: number;
        let vault: UnderwriterVaultMock;
        async function setup() {
          let {
            callVault,
            putVault,
            caller,
            deployer,
            base,
            quote,
            oracleAdapter,
            p,
          } = await loadFixture(vaultSetup);
          let deposit: number;
          maturity = await getValidMaturity(1, 'weeks');
          let token: ERC20Mock;

          if (isCall) {
            deposit = 10;
            token = base;
            vault = callVault;
            newLockedAfterSettlement = parseEther('1');
            newTotalAssets = 10.333333333333;
          } else {
            deposit = 10000;
            token = quote;
            vault = putVault;
            newLockedAfterSettlement = parseEther('1120');
            newTotalAssets = 9000;
          }

          console.log('Depositing assets.');
          await addMockDeposit(vault, deposit, base, quote);
          expect(await vault.totalAssets()).to.eq(
            parseUnits(deposit.toString(), await token.decimals()),
          );
          console.log('Deposited assets.');

          const infos = [
            {
              maturity: maturity,
              strikes: [strike1, strike2],
              sizes: [size, size],
            },
          ];
          await vault.setListingsAndSizes(infos);
          for (const strike of [strike1, strike2]) {
            await createPool(
              strike,
              maturity,
              isCall,
              deployer,
              base,
              quote,
              oracleAdapter,
              p,
            );
          }
          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, maturity)
            .returns(parseUnits('1500', 18));
          await vault.connect(caller).mintFromPool(strike1, maturity, size);
          await vault.connect(caller).mintFromPool(strike2, maturity, size);
          expect(await vault.totalLockedAssets()).to.eq(parseEther('4'));
          expect(await vault.totalAssets()).to.eq(parseEther('9.988'));
          await increaseTo(maturity);
          await vault.connect(caller).settleMaturity(maturity);
        }

        const callTest = { newLocked: 0, newTotalAssets: 9.321333333333333 };

        const putTest = { newLocked: 0, newTotalAssets: 0 };

        const test = isCall ? callTest : putTest;

        it(`totalAssets should be reduced by the exerciseValue and equal ${test.newTotalAssets}`, async () => {
          await loadFixture(setup);
          expect(
            parseFloat(formatEther(await vault.totalAssets())),
          ).to.be.closeTo(test.newTotalAssets, 0.000000000001);
        });
        it(`the position size should be reduced by the amount of settled options and equal ${test.newLocked}`, async () => {
          expect(await vault.totalLockedAssets()).to.eq(test.newLocked);
        });
      });
    }
  });

  describe('#settle', () => {
    const t0: number = 1678435200 + 2 * ONE_WEEK;
    const t1 = t0 + ONE_WEEK;
    const t2 = t0 + 2 * ONE_WEEK;
    let strikedict: { [key: number]: BigNumber[] } = {};
    let vault: UnderwriterVaultMock;

    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        async function setupVaultForSettlement() {
          let {
            callVault,
            putVault,
            deployer,
            caller,
            base,
            quote,
            oracleAdapter,
            p,
          } = await loadFixture(vaultSetup);

          let totalAssets: number;

          if (isCall) {
            vault = callVault;
            totalAssets = 100.03;
          } else {
            totalAssets = 100000;
            vault = putVault;
            await quote.mint(
              caller.address,
              parseEther(totalAssets.toString()),
            );
          }

          const striket00 = parseEther('1000');
          const striket01 = parseEther('2000');
          const striket10 = parseEther('1800');
          const striket20 = parseEther('1200');
          const striket21 = parseEther('1300');
          const striket22 = parseEther('2000');

          const strikest0 = [striket00, striket01];
          const strikest1 = [striket10];
          const strikest2 = [striket20, striket21, striket22];

          strikedict[t0] = strikest0;
          strikedict[t1] = strikest1;
          strikedict[t2] = strikest2;

          const infos = [
            {
              maturity: t0,
              strikes: strikest0,
              sizes: [2, 1].map((el) => parseEther(el.toString())),
            },
            {
              maturity: t1,
              strikes: strikest1,
              sizes: [1].map((el) => parseEther(el.toString())),
            },
            {
              maturity: t2,
              strikes: strikest2,
              sizes: [2, 3, 1].map((el) => parseEther(el.toString())),
            },
          ];

          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, t0)
            .returns(parseUnits('1500', 18));
          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, t1)
            .returns(parseUnits('1500', 18));
          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, t2)
            .returns(parseUnits('1500', 18));

          console.log('Depositing assets.');
          await addMockDeposit(vault, totalAssets, base, quote);
          expect(await vault.totalAssets()).to.eq(
            parseEther(totalAssets.toString()),
          );
          console.log('Deposited assets.');

          await vault.setListingsAndSizes(infos);
          //await vault.increaseTotalLockedAssets(totalLockedAssets);
          for (let info of infos) {
            for (const [i, strike] of info.strikes.entries()) {
              await createPool(
                strike,
                info.maturity,
                isCall,
                deployer,
                base,
                quote,
                oracleAdapter,
                p,
              );
              console.log(
                `Minting ${info.sizes[i]} options with strike ${strike} and maturity ${info.maturity}.`,
              );
              await vault
                .connect(caller)
                .mintFromPool(strike, info.maturity, info.sizes[i]);
            }
          }
          return { vault };
        }

        const tests = [
          { timestamp: t0 - ONE_HOUR, minMaturity: t0, maxMaturity: t2 },
          { timestamp: t0, minMaturity: t1, maxMaturity: t2 },
          { timestamp: t0 + ONE_HOUR, minMaturity: t1, maxMaturity: t2 },
          { timestamp: t1, minMaturity: t2, maxMaturity: t2 },
          { timestamp: t1 + ONE_HOUR, minMaturity: t2, maxMaturity: t2 },
          { timestamp: t2, minMaturity: 0, maxMaturity: 0 },
          { timestamp: t2 + ONE_HOUR, minMaturity: 0, maxMaturity: 0 },
        ];

        const callTests = [
          { newLocked: 10, newTotalAssets: 100 },
          { newLocked: 7, newTotalAssets: 99.333333 },
          { newLocked: 7, newTotalAssets: 99.333333 },
          { newLocked: 6, newTotalAssets: 99.333333 },
          { newLocked: 6, newTotalAssets: 99.333333 },
          { newLocked: 0, newTotalAssets: 98.533333 },
          { newLocked: 0, newTotalAssets: 98.533333 },
        ];

        const putTests = [
          { newLocked: 11300, newTotalAssets: 100000 },
          { newLocked: 7300, newTotalAssets: 99500 },
          { newLocked: 7300, newTotalAssets: 99500 },
          { newLocked: 5500, newTotalAssets: 99200 },
          { newLocked: 5500, newTotalAssets: 99200 },
          { newLocked: 0, newTotalAssets: 98700 },
          { newLocked: 0, newTotalAssets: 98700 },
        ];

        const amountsList = isCall ? callTests : putTests;
        let counter = 0;
        tests.forEach(async (test) => {
          let amounts = amountsList[counter];
          describe(`timestamp ${test.timestamp}`, () => {
            it(`totalAssets equals ${amounts.newTotalAssets}`, async () => {
              let { vault } = await loadFixture(setupVaultForSettlement);
              await increaseTo(test.timestamp);
              await vault.settle();
              let delta = isCall ? 0.00001 : 0;
              expect(
                parseFloat(formatEther(await vault.totalAssets())),
              ).to.be.closeTo(amounts.newTotalAssets, delta);
            });
            it(`totalLocked equals ${amounts.newLocked}`, async () => {
              let totalLocked = await vault.totalLockedAssets();
              let expected = parseEther(amounts.newLocked.toString());
              expect(totalLocked).to.eq(expected);
            });
            it(`minMaturity equals ${test.minMaturity}`, async () => {
              let minMaturity = await vault.minMaturity();
              expect(minMaturity).to.eq(test.minMaturity);
            });
            it(`maxMaturity equals ${test.maxMaturity}`, async () => {
              let maxMaturity = await vault.maxMaturity();
              expect(maxMaturity).to.eq(test.maxMaturity);
            });
            it(`expired position sizes equal zero`, async () => {
              if ([t0, t1, t2].includes(test.timestamp)) {
                let strikes = strikedict[test.timestamp];
                strikes.forEach(async (strike) => {
                  let size = await vault.positionSize(test.timestamp, strike);
                  expect(size).to.eq(parseEther('0'));
                });
              }
            });
            counter++;
          });
        });
      });
    }
  });

  describe('test getTotalLockedSpread and updateState', () => {
    /*
        Example

        |-----t0---t1-----t2---|

        Time to maturities starting from inception
        ---------------
        t0: 7 days
        t1: 10 days
        t2: 14 days

        Spread locked at inception
        ---------------
        t0: 1.24
        t1: 5.56
        t2: 11.2

        initial spreadUnlockingRate: (1.24 / 7 + 5.56 / 10 + 11.2 / 14) / (24 * 60 * 60)

        */
    let startTime: number;
    let t0: number;
    let t1: number;
    let t2: number;
    let spreadUnlockingRatet0: number;
    let spreadUnlockingRatet1: number;
    let spreadUnlockingRatet2: number;
    let spreadUnlockingRate: number;

    async function setupSpreadsVault() {
      const { callVault } = await loadFixture(vaultSetup);
      startTime = await latest();
      t0 = startTime + 7 * ONE_DAY;
      t1 = startTime + 10 * ONE_DAY;
      t2 = startTime + 14 * ONE_DAY;
      console.log('startTime', startTime);
      console.log('t0', t0);
      console.log('t1', t1);
      console.log('t2', t2);

      const infos = [
        {
          maturity: t0,
          strikes: [],
          sizes: [],
        },
        {
          maturity: t1,
          strikes: [],
          sizes: [],
        },
        {
          maturity: t2,
          strikes: [],
          sizes: [],
        },
        {
          maturity: 2 * t2,
          strikes: [],
          sizes: [],
        },
      ];
      await callVault.setListingsAndSizes(infos);
      await callVault.setLastSpreadUnlockUpdate(startTime);
      const totalLockedSpread = 1.24 + 5.56 + 11.2;
      console.log('totalLockedSpread', totalLockedSpread);
      const totalLockedFormatted = parseEther(totalLockedSpread.toString());
      spreadUnlockingRatet0 = 1.24 / (7 * ONE_DAY);
      spreadUnlockingRatet1 = 5.56 / (10 * ONE_DAY);
      spreadUnlockingRatet2 = 11.2 / (14 * ONE_DAY);
      const surt0 = parseEther(spreadUnlockingRatet0.toFixed(18).toString());
      const surt1 = parseEther(spreadUnlockingRatet1.toFixed(18).toString());
      const surt2 = parseEther(spreadUnlockingRatet2.toFixed(18).toString());

      console.log(spreadUnlockingRatet0);
      console.log(spreadUnlockingRatet1);
      console.log(spreadUnlockingRatet2);
      console.log(parseEther(spreadUnlockingRatet0.toFixed(18).toString()));
      console.log(parseEther(spreadUnlockingRatet1.toFixed(18).toString()));
      console.log(parseEther(spreadUnlockingRatet2.toFixed(18).toString()));

      await callVault.increaseSpreadUnlockingTick(t0, surt0);
      await callVault.increaseSpreadUnlockingTick(t1, surt1);
      await callVault.increaseSpreadUnlockingTick(t2, surt2);
      spreadUnlockingRate =
        spreadUnlockingRatet0 + spreadUnlockingRatet1 + spreadUnlockingRatet2;
      await callVault.increaseSpreadUnlockingRate(
        parseEther(spreadUnlockingRate.toFixed(18).toString()),
      );
      await callVault.increaseTotalLockedSpread(totalLockedFormatted);
      return { vault: callVault };
    }

    describe('#getTotalLockedSpread', () => {
      it('At startTime + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        let { vault } = await loadFixture(setupSpreadsVault);
        await increaseTo(startTime + ONE_DAY);
        expect(
          parseFloat(formatEther(await vault.getTotalLockedSpread())),
        ).to.be.closeTo(16.4668, 0.001);
      });

      it('At maturity t0 totalLockedSpread should approximately equal 7.268', async () => {
        // 7 / 14 * 11.2 + 3 / 10 * 5.56 = 7.268
        await increaseTo(t0);
        expect(
          parseFloat(formatEther(await vault.getTotalLockedSpread())),
        ).to.be.closeTo(7.268, 0.001);
      });

      it('At t0 + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        // 6 / 14 * 11.2 + 2 / 10 * 5.56 = 5.912
        await increaseTo(t0 + ONE_DAY);
        expect(
          parseFloat(formatEther(await vault.getTotalLockedSpread())),
        ).to.be.closeTo(5.912, 0.001);
      });

      it('At maturity t1 totalLockedSpread should approximately equal 3.2', async () => {
        // 11.2 * 3 / 14 = 3.2
        await increaseTo(t1);
        expect(
          parseFloat(formatEther(await vault.getTotalLockedSpread())),
        ).to.be.closeTo(3.2, 0.001);
      });

      it('At t1 + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        // 3 / 14 * 11.2 = 2.4
        await increaseTo(t1 + ONE_DAY);
        expect(
          parseFloat(formatEther(await vault.getTotalLockedSpread())),
        ).to.be.closeTo(2.4, 0.001);
      });

      it('At maturity t2 totalLockedSpread should approximately equal 0.0', async () => {
        // 0
        await increaseTo(t2);
        expect(
          parseFloat(formatEther(await vault.getTotalLockedSpread())),
        ).to.be.closeTo(0.0, 0.0000001);
      });

      it('At maturity t2 + 7 days totalLockedSpread should approximately equal 0.0', async () => {
        // 0
        await increaseTo(t2 + 7 * ONE_DAY);
        expect(
          parseFloat(formatEther(await vault.getTotalLockedSpread())),
        ).to.be.closeTo(0.0, 0.0000001);
      });
    });

    describe('#updateState', () => {
      it('At startTime + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        let { vault } = await loadFixture(setupSpreadsVault);
        await increaseTo(startTime + ONE_DAY);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(16.4668, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await latest());
      });

      it('At maturity t0 totalLockedSpread should approximately equal 7.268', async () => {
        // 7 / 14 * 11.2 + 3 / 10 * 5.56 = 7.268
        let { vault } = await loadFixture(setupSpreadsVault);
        await increaseTo(t0);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(7.268, 0.001);
        spreadUnlockingRate = spreadUnlockingRatet1 + spreadUnlockingRatet2;
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);

        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await latest());
      });

      it('At t0 + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        // 6 / 14 * 11.2 + 2 / 10 * 5.56 = 5.912
        let { vault } = await loadFixture(setupSpreadsVault);
        await increaseTo(t0 + ONE_DAY);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(5.912, 0.001);
        spreadUnlockingRate = spreadUnlockingRatet1 + spreadUnlockingRatet2;
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await latest());
      });

      it('At maturity t1 totalLockedSpread should approximately equal 3.2', async () => {
        // 11.2 * 3 / 14 = 3.2
        let { vault } = await loadFixture(setupSpreadsVault);
        await increaseTo(t1);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(3.2, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRatet2, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await latest());
      });

      it('At t1 + 1 day totalLockedSpread should approximately equal 7.268', async () => {
        // 3 / 14 * 11.2 = 2.4
        let { vault } = await loadFixture(setupSpreadsVault);
        await increaseTo(t1 + ONE_DAY);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(2.4, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRatet2, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await latest());
      });

      it('At maturity t2 totalLockedSpread should approximately equal 0.0', async () => {
        let { vault } = await loadFixture(setupSpreadsVault);
        await increaseTo(t2);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(0.0, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(0.0, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await latest());
      });

      it('Run through all of the above', async () => {
        let { vault } = await loadFixture(setupSpreadsVault);
        await increaseTo(startTime + ONE_DAY);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(16.4668, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await latest());
        await increaseTo(t0);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(7.268, 0.001);
        spreadUnlockingRate = spreadUnlockingRatet1 + spreadUnlockingRatet2;
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);

        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await latest());
        await increaseTo(t0 + ONE_DAY);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(5.912, 0.001);
        spreadUnlockingRate = spreadUnlockingRatet1 + spreadUnlockingRatet2;
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRate, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await latest());
        await increaseTo(t1);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(3.2, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRatet2, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await latest());
        await increaseTo(t1 + ONE_DAY);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(2.4, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(spreadUnlockingRatet2, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await latest());
        await increaseTo(t2);
        await vault.updateState();
        expect(
          parseFloat(formatEther(await vault.totalLockedSpread())),
        ).to.be.closeTo(0.0, 0.001);
        expect(
          parseFloat(formatEther(await vault.spreadUnlockingRate())),
        ).to.be.closeTo(0.0, 0.001);
        expect(await vault.lastSpreadUnlockUpdate()).to.eq(await latest());
      });
    });
  });

  describe('#_quote', () => {
    it('reverts on no strike input', async () => {
      const { base, quote, lp, callVault } = await loadFixture(vaultSetup);
      const badStrike = parseEther('0'); // ATM
      const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
      const quoteSize = parseEther('1');
      const lpDepositSize = 5; // units of base
      await addMockDeposit(callVault, lpDepositSize, base, quote);
      await expect(
        callVault.quote(badStrike, maturity, quoteSize),
      ).to.be.revertedWithCustomError(callVault, 'Vault__StrikeZero');
    });

    it('reverts on expired maturity input', async () => {
      const { base, quote, lp, callVault } = await loadFixture(vaultSetup);
      const strike = parseEther('1500'); // ATM
      const badMaturity = await time.latest();
      const quoteSize = parseEther('1');
      const lpDepositSize = 5; // units of base
      await addMockDeposit(callVault, lpDepositSize, base, quote);
      await expect(
        callVault.quote(strike, badMaturity, quoteSize),
      ).to.be.revertedWithCustomError(callVault, 'Vault__OptionExpired');
    });

    it('should revert due to too large incoming trade size', async () => {
      const { callVault, base, quote } = await loadFixture(vaultSetup);
      const lpDepositSize = 5;
      const largeTradeSize = parseEther('7');
      const strike = parseEther('1500');
      const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));

      await increaseTotalAssets(callVault, lpDepositSize, base, quote);
      await expect(
        callVault.quote(strike, maturity, largeTradeSize),
      ).to.be.revertedWithCustomError(callVault, 'Vault__InsufficientFunds');
    });

    it('returns proper quote parameters: price, mintingFee, cLevel', async () => {
      const { callVault, base, quote } = await loadFixture(vaultSetup);
      const lpDepositSize = 5;
      const tradeSize = parseEther('2');
      const strike = parseEther('1500');
      const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));

      await increaseTotalAssets(callVault, lpDepositSize, base, quote);
      // todo:

      const [, price, mintingFee, cLevel] = await callVault.quote(
        strike,
        maturity,
        tradeSize,
      );

      // Normalised price is in (0,1)
      expect(parseFloat(formatEther(price))).to.lt(1);
      expect(parseFloat(formatEther(price))).to.gt(0);

      // mintingFee == trade fee
      expect(parseFloat(formatEther(mintingFee))).to.eq(0.006);

      // check c-level
      expect(parseFloat(formatEther(cLevel))).to.approximately(1.024, 0.001);
    });

    it('reverts if maxCLevel is not set properly', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      const strike = parseEther('1500');
      const size = parseEther('2');
      const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
      await callVault.setMaxClevel(parseEther('0.0'));
      expect(
        callVault.quote(strike, maturity, size),
      ).to.be.revertedWithCustomError(callVault, 'Vault__CLevelBounds');
    });

    it('reverts if the C level alpha is not set properly', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      const strike = parseEther('1500');
      const size = parseEther('2');
      const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
      await callVault.setMaxClevel(parseEther('0.0'));
      expect(
        callVault.quote(strike, maturity, size),
      ).to.be.revertedWithCustomError(callVault, 'Vault__CLevelBounds');
    });
  });

  describe('#_getFactoryAddress', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('should return the poolAddress', async () => {
          const {
            callVault,
            putVault,
            strike,
            maturity,
            callPoolAddress,
            putPoolAddress,
          } = await loadFixture(vaultSetup);
          let relevantAddress: string;
          if (isCall) {
            vault = callVault;
            relevantAddress = callPoolAddress;
          } else {
            vault = putVault;
            relevantAddress = putPoolAddress;
          }
          const poolAddress = await vault.getFactoryAddress(strike, maturity);
          await expect(poolAddress).to.eq(relevantAddress);
        });

        it('reverts when factory returns addressZERO, i.e. the pool does not exist', async () => {
          const { callVault, putVault, strike, maturity } = await loadFixture(
            vaultSetup,
          );
          const badStrike = parseEther('100');
          const badMaturity = 10000000;

          if (isCall) vault = callVault;
          else vault = putVault;

          await expect(
            vault.getFactoryAddress(badStrike, maturity),
          ).to.be.revertedWithCustomError(vault, 'Vault__OptionPoolNotListed');

          await expect(
            vault.getFactoryAddress(strike, badMaturity),
          ).to.be.revertedWithCustomError(vault, 'Vault__OptionPoolNotListed');

          await expect(
            vault.getFactoryAddress(badStrike, badMaturity),
          ).to.be.revertedWithCustomError(vault, 'Vault__OptionPoolNotListed');
        });
      });
    }
  });

  describe('#_calculateCLevel', () => {
    describe('#cLevel calculation', () => {
      it('will not exceed max c-level', async () => {
        const { callVault } = await loadFixture(vaultSetup);
        const cLevel = await callVault.calculateClevel(
          parseEther('1.0'),
          parseEther('3.0'),
          parseEther('1.0'),
          parseEther('1.2'),
        );
        expect(parseFloat(formatEther(cLevel))).to.eq(1.2);
      });

      it('will not go below min c-level', async () => {
        const { callVault } = await loadFixture(vaultSetup);
        const cLevel = await callVault.calculateClevel(
          parseEther('0.0'),
          parseEther('3.0'),
          parseEther('1.0'),
          parseEther('1.2'),
        );
        expect(parseFloat(formatEther(cLevel))).to.eq(1.0);
      });

      it('will properly adjust based on utilization', async () => {
        const { callVault } = await loadFixture(vaultSetup);

        let cLevel = await callVault.calculateClevel(
          parseEther('0.4'), // 40% utilization
          parseEther('3.0'),
          parseEther('1.0'),
          parseEther('1.2'),
        );
        expect(parseFloat(formatEther(cLevel))).to.approximately(1.024, 0.001);

        cLevel = await callVault.calculateClevel(
          parseEther('0.9'),
          parseEther('3.0'),
          parseEther('1.0'),
          parseEther('1.2'),
        );
        expect(parseFloat(formatEther(cLevel))).to.approximately(1.145, 0.001);
      });
    });

    describe('#trade', () => {
      it('used post quote/trade utilization', async () => {
        const { callVault, lp, trader, base, quote } = await loadFixture(
          vaultSetup,
        );

        // Hydrate Vault
        const lpDepositSize = 5; // units of base
        await addMockDeposit(callVault, lpDepositSize, base, quote);
        // Trade Settings
        const strike = parseEther('1500');
        const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
        const tradeSize = parseEther('2');

        // Execute Trade
        const cLevel_postTrade = await callVault.getClevel(tradeSize);
        const [, premium, mintingFee, spread] = await callVault.quote(
          strike,
          maturity,
          tradeSize,
        );
        const totalTransfer = premium.add(mintingFee).add(spread);
        await base.connect(trader).approve(callVault.address, totalTransfer);
        await callVault
          .connect(trader)
          .trade(strike, maturity, true, tradeSize, true);
        const cLevel_postTrade_check = await callVault.getClevel(
          parseEther('0'),
        );
        // Approx due to premium collection
        expect(parseFloat(formatEther(cLevel_postTrade))).to.approximately(
          parseFloat(formatEther(cLevel_postTrade_check)),
          0.002,
        );
      });

      it('ensures utilization never goes over 100%', async () => {
        const { callVault, lp, trader, base, quote } = await loadFixture(
          vaultSetup,
        );

        // Hydrate Vault
        const lpDepositSize = 5; // units of base

        await addMockDeposit(callVault, lpDepositSize, base, quote);

        // Trade Settings
        const strike = parseEther('1500');
        const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
        const tradeSize = parseEther('3');

        // Execute Trades
        // todo: compute price + mintingFee without using quote
        const [, premium, mintingFee, spread] = await callVault.quote(
          strike,
          maturity,
          tradeSize,
        );
        const totalTransfer = premium.add(mintingFee).add(spread);
        await base.connect(trader).approve(callVault.address, totalTransfer);
        await callVault
          .connect(trader)
          .trade(strike, maturity, true, tradeSize, true);

        await expect(
          callVault
            .connect(trader)
            .trade(strike, maturity, true, tradeSize, true),
        ).to.revertedWithCustomError(callVault, 'Vault__InsufficientFunds');
      });

      it('properly updates for last trade timestamp', async () => {
        const { callVault, lp, trader, base, quote } = await loadFixture(
          vaultSetup,
        );

        // Hydrate Vault
        const lpDepositSize = 5; // units of base
        await addMockDeposit(callVault, lpDepositSize, base, quote);

        // Trade Settings
        const strike = parseEther('1500');
        const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
        const tradeSize = parseEther('2');

        // Initialized lastTradeTimestamp
        const lastTrade_t0 = await callVault.getLastTradeTimestamp();

        // Execute Trade
        const [, premium, mintingFee, spread] = await callVault.quote(
          strike,
          maturity,
          tradeSize,
        );
        const totalTransfer = premium.add(mintingFee).add(spread);
        await base.connect(trader).approve(callVault.address, totalTransfer);
        await callVault
          .connect(trader)
          .trade(strike, maturity, true, tradeSize, true);

        const lastTrade_t1 = await callVault.getLastTradeTimestamp();

        expect(lastTrade_t1).to.be.gt(lastTrade_t0);
      });

      it('properly decays the c Level over time', async () => {
        const { callVault, lp, trader, base, quote } = await loadFixture(
          vaultSetup,
        );

        // Hydrate Vault
        const lpDepositSize = 5; // units of base
        await addMockDeposit(callVault, lpDepositSize, base, quote);

        // Trade Settings
        const strike = parseEther('1500');
        const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
        const tradeSize = parseEther('2');

        //PreTrade cLevel
        const cLevel_t0 = await callVault.getClevel(parseEther('0'));

        // Execute Trade
        const cLevel_t1 = await callVault.getClevel(tradeSize);

        const [, premium, mintingFee, spread] = await callVault.quote(
          strike,
          maturity,
          tradeSize,
        );
        const totalTransfer = premium.add(mintingFee).add(spread);
        await base.connect(trader).approve(callVault.address, totalTransfer);

        await callVault
          .connect(trader)
          .trade(strike, maturity, true, tradeSize, true);
        const cLevel_t2 = await callVault.getClevel(tradeSize);
        // Increase time by 2 hrs
        await time.increase(7200);
        // Check final c-level
        const cLevel_t3 = await callVault.getClevel(tradeSize);

        expect(parseFloat(formatEther(cLevel_t0))).to.be.eq(1);
        expect(parseFloat(formatEther(cLevel_t1))).to.be.gt(1);
        expect(cLevel_t2).to.be.gt(cLevel_t1);
        expect(cLevel_t2).to.be.gt(cLevel_t3);
      });
    });
  });
});
