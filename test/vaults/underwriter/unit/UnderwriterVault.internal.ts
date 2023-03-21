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
import { BigNumber, ethers } from 'ethers';
import { setMaturities } from '../VaultSetup';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

let vault: UnderwriterVaultMock;
let token: ERC20Mock;

let startTime: number = 2 * 1679395050;
let t0: number = startTime + 7 * ONE_DAY;
let t1: number = startTime + 10 * ONE_DAY;
let t2: number = startTime + 14 * ONE_DAY;

async function setupSpreadsVault() {
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

  spreadUnlockingRate(t<t0): (1.24 / 7 + 5.56 / 10 + 11.2 / 14) / (24 * 60 * 60) = 0.0000177447
  spreadUnlockingRate(t0<=t<t1): (5.56 / 10 + 11.2 / 14) / (24 * 60 * 60) = 0.00001569444
  spreadUnlockingRate(t1<=t<t2): (11.2 / 14) / (24 * 60 * 60) = 0.00000925925
  spreadUnlockingRate(t2<=t): 0
  */
  const { callVault } = await loadFixture(vaultSetup);

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
  const totalLockedFormatted = parseEther(totalLockedSpread.toString());
  const spreadUnlockingRatet0 = 1.24 / (7 * ONE_DAY);
  const spreadUnlockingRatet1 = 5.56 / (10 * ONE_DAY);
  const spreadUnlockingRatet2 = 11.2 / (14 * ONE_DAY);
  const spreadUnlockingRate =
    spreadUnlockingRatet0 + spreadUnlockingRatet1 + spreadUnlockingRatet2;

  const surt0 = parseEther(spreadUnlockingRatet0.toFixed(18).toString());
  const surt1 = parseEther(spreadUnlockingRatet1.toFixed(18).toString());
  const surt2 = parseEther(spreadUnlockingRatet2.toFixed(18).toString());
  const surgl = parseEther(spreadUnlockingRate.toFixed(18).toString());
  await callVault.increaseSpreadUnlockingTick(t0, surt0);
  await callVault.increaseSpreadUnlockingTick(t1, surt1);
  await callVault.increaseSpreadUnlockingTick(t2, surt2);
  await callVault.increaseSpreadUnlockingRate(surgl);
  await callVault.increaseTotalLockedSpread(totalLockedFormatted);
  return { vault: callVault };
}

describe('UnderwriterVault', () => {
  describe('#_availableAssets', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        before(async () => {
          const { callVault, putVault, caller, receiver, base, quote } =
            await loadFixture(vaultSetup);
          vault = isCall ? callVault : putVault;
          token = isCall ? base : quote;
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
          await vault.increaseTotalLockedAssets(
            parseUnits('0.5', await token.decimals()),
          );
          expect(await vault.getAvailableAssets()).to.eq(parseEther('1.498'));
        });
        it('expected to equal (totalAssets - totalLockedSpread - totalLockedAssets) = 1.298', async () => {
          await vault.increaseTotalLockedSpread(parseEther('0.2'));
          expect(await vault.getAvailableAssets()).to.eq(parseEther('1.298'));
        });
        it('expected to equal (totalAssets - totalLockedSpread - totalLockedAssets) = 1.2979', async () => {
          await vault.increaseTotalLockedAssets(
            parseUnits('0.0001', await token.decimals()),
          );
          expect(await vault.getAvailableAssets()).to.eq(parseEther('1.2979'));
        });
      });
    }
  });

  describe('#_afterBuy', () => {
    const spread = 10;
    const size = 1;
    const strike = 100;
    let lockedAmount: number;

    async function setupAfterBuyVault(isCall: boolean) {
      // afterBuy function is independent of call / put option type
      const { vault } = await loadFixture(setupSpreadsVault);
      expect(await vault.spreadUnlockingRate()).to.eq('17744708994709');
      await vault.setIsCall(isCall);
      console.log('Setup vault.');

      await vault.increasePositionSize(
        t0,
        parseEther(strike.toString()),
        parseEther('1.234'),
      );
      lockedAmount = isCall ? 1.234 : 1.234 * strike;
      await vault.increaseTotalLockedAssetsNoTransfer(
        parseEther(lockedAmount.toString()),
      );

      const ZERO = parseEther('0');
      const afterBuyArgs = {
        maturity: t0,
        size: parseEther(size.toString()),
        spread: parseEther(spread.toString()),
        strike: parseEther(strike.toString()),
        timestamp: startTime + ONE_DAY,
        spot: ZERO,
        poolAddr: ethers.constants.AddressZero,
        tau: ZERO,
        sigma: ZERO,
        delta: ZERO,
        premium: ZERO,
        cLevel: ZERO,
        riskFreeRate: ZERO,
        price: ZERO,
        mintingFee: ZERO,
      };
      await increaseTo(startTime + ONE_DAY);
      await vault.afterBuy(afterBuyArgs);
      console.log('Processed afterBuy.');
      return { vault };
    }

    it('lastSpreadUnlockUpdate should equal the time we executed afterBuy as we updated the state there', async () => {
      const { vault } = await setupAfterBuyVault(true);
      const lsuu = await vault.lastSpreadUnlockUpdate();
      expect(parseInt(lsuu)).to.eq(startTime + ONE_DAY);
    });

    it('spreadUnlockingRates should equal 34279100529100', async () => {
      const { vault } = await setupAfterBuyVault(true);
      expect(await vault.spreadUnlockingRate()).to.eq('37034832451499');
    });

    it('positionSize should be incremented by the bought amount and equal 2.234', async () => {
      const { vault } = await setupAfterBuyVault(true);
      const x = parseEther(strike.toString());
      const positionSize = await vault.positionSize(t0, x);
      expect(parseFloat(formatEther(positionSize))).to.eq(1.234 + size);
    });

    it('spreadUnlockingTick should be incremented by the spread amount divided by the the time to maturity', async () => {
      const { vault } = await setupAfterBuyVault(true);
      const sut = parseFloat(formatEther(await vault.spreadUnlockingTicks(t0)));
      const increment = 10 / (6 * ONE_DAY);
      const sur = 1.24 / (7 * ONE_DAY) + increment;
      const sutExpected = parseFloat(sur.toFixed(18));
      expect(sut).to.eq(sutExpected);
    });

    it('totalLockedSpread should be incremented by the spread earned (10) after updating the state', async () => {
      const { vault } = await setupAfterBuyVault(true);
      // updateState:
      //  totalLockedSpread = totalLockedSpread - SUR_OLD * timePassed;
      //
      const a =
        18 - parseFloat(formatEther('17744708994709')) * ONE_DAY + spread;
      expect(parseFloat(formatEther(await vault.totalLockedSpread()))).to.eq(a);
    });

    it('lastTradeTimestamp should equal timestamp (startTime + ONE_DAY)', async () => {
      const { vault } = await setupAfterBuyVault(true);
      expect(parseInt(await vault.getLastTradeTimestamp())).to.eq(
        startTime + ONE_DAY,
      );
    });

    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('totalLockedAssets should equal', async () => {
          const { vault } = await setupAfterBuyVault(isCall);
          let totalLocked = isCall ? size : size * strike;
          totalLocked += lockedAmount;
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

  describe('#_getLockedSpreadVars and #_updateState', () => {
    const tests = [
      {
        timestamp: startTime + ONE_DAY,
        totalLockedSpread: 16.4668,
        spreadUnlockingRate: 0.0000177447,
      },
      {
        timestamp: t0,
        totalLockedSpread: 7.268,
        spreadUnlockingRate: 0.00001569444,
      },
      {
        timestamp: t0 + ONE_DAY,
        totalLockedSpread: 5.912,
        spreadUnlockingRate: 0.00001569444,
      },
      {
        timestamp: t1,
        totalLockedSpread: 3.2,
        spreadUnlockingRate: 0.00000925925,
      },
      {
        timestamp: t1 + ONE_DAY,
        totalLockedSpread: 2.4,
        spreadUnlockingRate: 0.00000925925,
      },
      {
        timestamp: t2,
        totalLockedSpread: 0.0,
        spreadUnlockingRate: 0.0,
      },
    ];

    describe('#_getLockedSpreadVars', () => {
      tests.forEach(async (test) => {
        it(`at timestamp ${test.timestamp} totalLockedSpread equals ${test.totalLockedSpread} and spreadUnlockingRate equals ${test.spreadUnlockingRate}.`, async () => {
          let { vault } = await loadFixture(setupSpreadsVault);
          await increaseTo(test.timestamp);
          const [
            totalLockedSpread,
            spreadUnlockingRate,
            lastSpreadUnlockUpdate,
          ] = await vault.getLockedSpreadVars(test.timestamp);
          const tlsParsed = parseFloat(formatEther(totalLockedSpread));
          const surParsed = parseFloat(formatEther(spreadUnlockingRate));
          expect(tlsParsed).to.be.closeTo(test.totalLockedSpread, 0.001);
          expect(surParsed).to.be.closeTo(
            test.spreadUnlockingRate,
            0.0000000001,
          );
          expect(parseInt(lastSpreadUnlockUpdate)).to.eq(test.timestamp);

          // assert that stored variables are not overwritten
          const tlsStoredParsed = parseFloat(
            formatEther(await vault.totalLockedSpread()),
          );
          const surStoredParsed = parseFloat(
            formatEther(await vault.spreadUnlockingRate()),
          );
          const lsuuParsed = parseInt(await vault.lastSpreadUnlockUpdate());
          expect(tlsStoredParsed).to.eq(18);
          expect(surStoredParsed).to.be.closeTo(0.0000177447, 0.0000000001);
          expect(lsuuParsed).to.eq(startTime);
        });
      });
    });

    describe('#_updateState', () => {
      tests.forEach(async (test) => {
        it(`at timestamp ${test.timestamp} totalLockedSpread equals ${test.totalLockedSpread} and spreadUnlockingRate equals ${test.spreadUnlockingRate}.`, async () => {
          let { vault } = await loadFixture(setupSpreadsVault);
          await increaseTo(test.timestamp);
          await vault.updateState(test.timestamp);
          const tlsParsed = parseFloat(
            formatEther(await vault.totalLockedSpread()),
          );
          const surParsed = parseFloat(
            formatEther(await vault.spreadUnlockingRate()),
          );
          const lsuuParsed = parseInt(await vault.lastSpreadUnlockUpdate());
          expect(tlsParsed).to.be.closeTo(test.totalLockedSpread, 0.001);
          expect(surParsed).to.be.closeTo(
            test.spreadUnlockingRate,
            0.0000000001,
          );
          expect(lsuuParsed).to.eq(test.timestamp);
        });
      });
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
});
