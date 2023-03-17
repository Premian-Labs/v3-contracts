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
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

let startTime: number;
let spot: number;
let minMaturity: number;
let maxMaturity: number;

let t0: number;
let t1: number;
let t2: number;
let t3: number;

let vault: UnderwriterVaultMock;

let caller: SignerWithAddress;
let base: ERC20Mock;
let quote: ERC20Mock;

describe('UnderwriterVault', () => {
  describe('#_getTotalLiabilitiesExpired', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        startTime = 100000;

        t0 = startTime + 7 * ONE_DAY;
        t1 = startTime + 10 * ONE_DAY;
        t2 = startTime + 14 * ONE_DAY;
        t3 = startTime + 30 * ONE_DAY;

        before(async () => {
          const { callVault, oracleAdapter, base, quote } = await loadFixture(
            vaultSetup,
          );
          vault = callVault;

          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, t0)
            .returns(parseUnits('1000', 18));
          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, t1)
            .returns(parseUnits('1400', 18));
          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, t2)
            .returns(parseUnits('1600', 18));
          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, t3)
            .returns(parseUnits('1000', 18));

          const infos = [
            {
              maturity: t0,
              strikes: [800, 900, 1500, 2000].map((el) =>
                parseEther(el.toString()),
              ),
              sizes: [1, 2, 2, 1].map((el) => parseEther(el.toString())),
            },
            {
              maturity: t1,
              strikes: [700, 900, 1500].map((el) => parseEther(el.toString())),
              sizes: [1, 5, 1].map((el) => parseEther(el.toString())),
            },
            {
              maturity: t2,
              strikes: [800, 1500, 2000].map((el) => parseEther(el.toString())),
              sizes: [1, 2, 1].map((el) => parseEther(el.toString())),
            },
            {
              maturity: t3,
              strikes: [900, 1500].map((el) => parseEther(el.toString())),
              sizes: [2, 2].map((el) => parseEther(el.toString())),
            },
          ];
          await callVault.setListingsAndSizes(infos);
        });

        let callTests = [
          { isCall: true, timestamp: t0 - ONE_DAY, expected: 0 },
          { isCall: true, timestamp: t0, expected: 0.4 },
          { isCall: true, timestamp: t0 + ONE_DAY, expected: 0.4 },
          { isCall: true, timestamp: t1, expected: 0.4 + 2.28571428571 },
          {
            isCall: true,
            timestamp: t1 + ONE_DAY,
            expected: 0.4 + 2.28571428571,
          },
          {
            isCall: true,
            timestamp: t2 + ONE_DAY,
            expected: 2.68571428571 + 0.625,
          },
          {
            isCall: true,
            timestamp: t3,
            expected: 2.68571428571 + 0.625 + 0.2,
          },
          {
            isCall: true,
            timestamp: t3 + ONE_DAY,
            expected: 2.68571428571 + 0.625 + 0.2,
          },
        ];

        let putTests = [
          { isCall: false, timestamp: t0 - ONE_DAY, expected: 0 },
          { isCall: false, timestamp: t0, expected: 2000 },
          { isCall: false, timestamp: t0 + ONE_DAY, expected: 2000 },
          { isCall: false, timestamp: t1, expected: 2000 + 100 },
          { isCall: false, timestamp: t1 + ONE_DAY, expected: 2000 + 100 },
          { isCall: false, timestamp: t2 + ONE_DAY, expected: 2100 + 400 },
          { isCall: false, timestamp: t3, expected: 2100 + 400 + 1000 },
          {
            isCall: false,
            timestamp: t3 + ONE_DAY,
            expected: 2100 + 400 + 1000,
          },
        ];

        let tests = isCall ? callTests : putTests;

        tests.forEach(async (test) => {
          it(`returns ${test.expected} when isCall=${test.isCall} and timestamp=${test.timestamp}`, async () => {
            await vault.setIsCall(test.isCall);
            let result = await vault.getTotalLiabilitiesExpired(test.timestamp);
            let delta = test.isCall ? 0.00001 : 0.0;

            expect(parseFloat(formatEther(result))).to.be.closeTo(
              test.expected,
              delta,
            );
          });
        });

        it('returns 0 when there are no existing listings', async () => {
          await vault.clearListingsAndSizes();

          let result = await vault.getTotalLiabilitiesExpired(t0 - ONE_DAY);
          let expected = 0;

          expect(result).to.eq(parseEther(expected.toString()));

          await vault.setIsCall(false);

          result = await vault.getTotalLiabilitiesExpired(t0 - ONE_DAY);
          expected = 0;

          expect(result).to.eq(parseEther(expected.toString()));
        });
      });
    }
  });

  describe('#_getTotalLiabilitiesUnexpired', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        let startTime = 100000;

        let t0 = startTime + 7 * ONE_DAY;
        let t1 = startTime + 10 * ONE_DAY;
        let t2 = startTime + 14 * ONE_DAY;
        let t3 = startTime + 30 * ONE_DAY;
        let spot = parseEther('1000');

        before(async () => {
          const { callVault } = await loadFixture(vaultSetup);
          vault = callVault;

          const infos = [
            {
              maturity: t0,
              strikes: [800, 900, 1500, 2000].map((el) =>
                parseEther(el.toString()),
              ),
              sizes: [1, 2, 2, 1].map((el) => parseEther(el.toString())),
            },
            {
              maturity: t1,
              strikes: [700, 900, 1500].map((el) => parseEther(el.toString())),
              sizes: [1, 5, 1].map((el) => parseEther(el.toString())),
            },
            {
              maturity: t2,
              strikes: [800, 1500, 2000].map((el) => parseEther(el.toString())),
              sizes: [1, 2, 1].map((el) => parseEther(el.toString())),
            },
            {
              maturity: t3,
              strikes: [900, 1500].map((el) => parseEther(el.toString())),
              sizes: [2, 2].map((el) => parseEther(el.toString())),
            },
          ];
          await vault.setListingsAndSizes(infos);
        });

        let callTests = [
          {
            isCall: true,
            timestamp: t0 - ONE_DAY,
            expected: 1.697282885495867,
          },
          { isCall: true, timestamp: t0, expected: 1.2853079354050814 },
          {
            isCall: true,
            timestamp: t0 + ONE_DAY,
            expected: 1.2755281851488665,
          },
          {
            isCall: true,
            timestamp: t2 + ONE_DAY,
            expected: 0.24420148996961677,
          },
          { isCall: true, timestamp: t3, expected: 0 },
          { isCall: true, timestamp: t3 + ONE_DAY, expected: 0 },
        ];

        let putTests = [
          {
            isCall: false,
            timestamp: t0 - ONE_DAY,
            expected: 5597.282885495868,
          },
          { isCall: false, timestamp: t0, expected: 3585.3079354050824 },
          {
            isCall: false,
            timestamp: t0 + ONE_DAY,
            expected: 3575.528185148866,
          },
          {
            isCall: false,
            timestamp: t2 + ONE_DAY,
            expected: 1044.2014899696167,
          },
          { isCall: false, timestamp: t3, expected: 0 },
          { isCall: false, timestamp: t3 + ONE_DAY, expected: 0 },
        ];

        let tests = isCall ? callTests : putTests;

        tests.forEach(async (test) => {
          it(`returns ${test.expected} when isCall=${test.isCall} and timestamp=${test.timestamp}`, async () => {
            await vault.setIsCall(test.isCall);
            let result = await vault.getTotalLiabilitiesUnexpired(
              test.timestamp,
              spot,
            );
            let delta = test.isCall ? 0.00001 : 0.01;

            expect(parseFloat(formatEther(result))).to.be.closeTo(
              test.expected,
              delta,
            );
          });
        });

        it('returns 0 when there are no existing listings', async () => {
          await vault.clearListingsAndSizes();

          let result = await vault.getTotalLiabilitiesUnexpired(
            t0 - ONE_DAY,
            spot,
          );
          let expected = 0;

          expect(result).to.eq(parseEther(expected.toString()));

          await vault.setIsCall(false);

          result = await vault.getTotalLiabilitiesUnexpired(t0 - ONE_DAY, spot);
          expected = 0;

          expect(result).to.eq(parseEther(expected.toString()));
        });
      });
    }
  });

  describe('#_getTotalLiabilities', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        const currentTime = 1878113571;
        const t0 = currentTime + 7 * ONE_DAY;
        const t1 = currentTime + 10 * ONE_DAY;
        const t2 = currentTime + 14 * ONE_DAY;
        const t3 = currentTime + 30 * ONE_DAY;

        let vault: UnderwriterVaultMock;

        const infos = [
          {
            maturity: t0,
            strikes: [800, 900, 1500, 2000].map((el) =>
              parseEther(el.toString()),
            ),
            sizes: [1, 2, 2, 1].map((el) => parseEther(el.toString())),
          },
          {
            maturity: t1,
            strikes: [700, 900, 1500].map((el) => parseEther(el.toString())),
            sizes: [1, 5, 1].map((el) => parseEther(el.toString())),
          },
          {
            maturity: t2,
            strikes: [800, 1500, 2000].map((el) => parseEther(el.toString())),
            sizes: [1, 2, 1].map((el) => parseEther(el.toString())),
          },
          {
            maturity: t3,
            strikes: [900, 1500].map((el) => parseEther(el.toString())),
            sizes: [2, 2].map((el) => parseEther(el.toString())),
          },
        ];

        before(async () => {
          const { callVault, oracleAdapter, base, quote } = await loadFixture(
            vaultSetup,
          );
          vault = callVault;

          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, t0)
            .returns(parseUnits('1000', 18));
          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, t1)
            .returns(parseUnits('1400', 18));
          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, t2)
            .returns(parseUnits('1600', 18));
          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, t3)
            .returns(parseUnits('1000', 18));

          await vault.setListingsAndSizes(infos);
        });

        let callTests = [
          { isCall: true, timestamp: t0 - ONE_DAY, expected: 5.37163 },
          { isCall: true, timestamp: t0, expected: 4.45834 },
          { isCall: true, timestamp: t0 + ONE_DAY, expected: 4.44419 },
          { isCall: true, timestamp: t1, expected: 4.15323 },
          { isCall: true, timestamp: t1 + ONE_DAY, expected: 4.14161 },
          { isCall: true, timestamp: t2 + ONE_DAY, expected: 4.22983 },
          { isCall: true, timestamp: t3, expected: 3.51071 },
          { isCall: true, timestamp: t3 + ONE_DAY, expected: 3.51071 },
        ];

        let putTests = [
          /*{ isCall: false, timestamp: t0 - ONE_DAY, expected: 1457.45 },
                              { isCall: false, timestamp: t0, expected: 2887.51 },
                              { isCall: false, timestamp: t0 + ONE_DAY, expected: 2866.29 },
                              { isCall: false, timestamp: t1, expected: 2901.27 },
                              { isCall: false, timestamp: t1 + ONE_DAY, expected: 2883.85 },
                              { isCall: false, timestamp: t2 + ONE_DAY, expected: 2678.67948 },
                              { isCall: false, timestamp: t3, expected: 3500 },*/
          { isCall: false, timestamp: t3 + ONE_DAY, expected: 3500 },
        ];

        let tests = isCall ? callTests : putTests;

        tests.forEach(async (test) => {
          it(`returns ${test.expected} when isCall=${test.isCall} and timestamp=${test.timestamp}`, async () => {
            await vault.setIsCall(test.isCall);
            if (test.isCall) await increaseTo(test.timestamp);
            let result = await vault.getTotalLiabilities();
            let delta = test.isCall ? 0.00001 : 0.01;

            expect(parseFloat(formatEther(result))).to.be.closeTo(
              test.expected,
              delta,
            );
          });
        });
      });
    }
  });

  describe('#_getTotalFairValue', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        const currentTime = 1878113571;
        const t0 = currentTime + 7 * ONE_DAY;
        const t1 = currentTime + 10 * ONE_DAY;
        const t2 = currentTime + 14 * ONE_DAY;
        const t3 = currentTime + 30 * ONE_DAY;

        let vault: UnderwriterVaultMock;

        const infos = [
          {
            maturity: t0,
            strikes: [800, 900, 1500, 2000].map((el) =>
              parseEther(el.toString()),
            ),
            sizes: [1, 2, 2, 1].map((el) => parseEther(el.toString())),
          },
          {
            maturity: t1,
            strikes: [700, 900, 1500].map((el) => parseEther(el.toString())),
            sizes: [1, 5, 1].map((el) => parseEther(el.toString())),
          },
          {
            maturity: t2,
            strikes: [800, 1500, 2000].map((el) => parseEther(el.toString())),
            sizes: [1, 2, 1].map((el) => parseEther(el.toString())),
          },
          {
            maturity: t3,
            strikes: [900, 1500].map((el) => parseEther(el.toString())),
            sizes: [2, 2].map((el) => parseEther(el.toString())),
          },
        ];

        let totalLockedCall = 0;
        let totalLockedPut = 0;

        for (let i = 0; i < infos.length; i++) {
          for (let j = 0; j < infos[i].strikes.length; j++) {
            let strike = parseFloat(formatEther(infos[i].strikes[j]));
            let size = parseFloat(formatEther(infos[i].sizes[j]));

            totalLockedCall += size;
            totalLockedPut += strike * size;
          }
        }

        before(async () => {
          const { callVault, oracleAdapter, base, quote } = await loadFixture(
            vaultSetup,
          );
          vault = callVault;

          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, t0)
            .returns(parseUnits('1000', 18));
          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, t1)
            .returns(parseUnits('1400', 18));
          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, t2)
            .returns(parseUnits('1600', 18));
          await oracleAdapter.mock.quoteFrom
            .withArgs(base.address, quote.address, t3)
            .returns(parseUnits('1000', 18));

          await vault.setListingsAndSizes(infos);
        });

        let callTests = [
          {
            isCall: true,
            timestamp: t0 - ONE_DAY,
            expected: totalLockedCall - 5.37163,
          },
          { isCall: true, timestamp: t0, expected: totalLockedCall - 4.45834 },
          {
            isCall: true,
            timestamp: t0 + ONE_DAY,
            expected: totalLockedCall - 4.44419,
          },
          { isCall: true, timestamp: t1, expected: totalLockedCall - 4.15323 },
          {
            isCall: true,
            timestamp: t1 + ONE_DAY,
            expected: totalLockedCall - 4.14161,
          },
          {
            isCall: true,
            timestamp: t2 + ONE_DAY,
            expected: totalLockedCall - 4.22983,
          },
          { isCall: true, timestamp: t3, expected: totalLockedCall - 3.51071 },
          {
            isCall: true,
            timestamp: t3 + ONE_DAY,
            expected: totalLockedCall - 3.51071,
          },
        ];

        let putTests = [
          {
            isCall: false,
            timestamp: t0 - ONE_DAY,
            expected: totalLockedPut - 1457.45,
          },
          { isCall: false, timestamp: t0, expected: totalLockedPut - 2887.51 },
          {
            isCall: false,
            timestamp: t0 + ONE_DAY,
            expected: totalLockedPut - 2866.29,
          },
          { isCall: false, timestamp: t1, expected: totalLockedPut - 2901.27 },
          {
            isCall: false,
            timestamp: t1 + ONE_DAY,
            expected: totalLockedPut - 2883.85,
          },
          {
            isCall: false,
            timestamp: t2 + ONE_DAY,
            expected: totalLockedPut - 2678.67948,
          },
          { isCall: false, timestamp: t3, expected: totalLockedPut - 3500 },
          {
            isCall: false,
            timestamp: t3 + ONE_DAY,
            expected: totalLockedPut - 3500,
          },
        ];

        let tests = isCall ? callTests : putTests;

        tests.forEach(async (test) => {
          let totalLocked = test.isCall ? totalLockedCall : totalLockedPut;

          it(`returns ${test.expected} when isCall=${test.isCall} and timestamp=${test.timestamp}`, async () => {
            await vault.setIsCall(test.isCall);
            await vault.setTotalLockedAssets(
              parseEther(totalLocked.toString()),
            );

            if (test.isCall) await increaseTo(test.timestamp);
            let result = await vault.getTotalFairValue();
            let delta = test.isCall ? 0.00001 : 0.01;

            expect(parseFloat(formatEther(result))).to.be.closeTo(
              test.expected,
              delta,
            );
          });
        });
      });
    }
  });

  describe('#_getPricePerShare', () => {
    let tests = [
      { expected: 1, deposit: 2, totalLockedSpread: 0, tradeSize: 0 },
      { expected: 0.9, deposit: 2, totalLockedSpread: 0.2, tradeSize: 0 },
      { expected: 0.98, deposit: 5, totalLockedSpread: 0.1, tradeSize: 0 },
      {
        expected: 0.56666666,
        deposit: 2,
        totalLockedSpread: 0.2,
        tradeSize: 1,
      },
      {
        expected: 0.66666666,
        deposit: 2,
        totalLockedSpread: 0,
        tradeSize: 1,
      },
    ];
    tests.forEach(async (test) => {
      it(`returns ${test.expected} when totalLockedSpread=${test.totalLockedSpread} and tradeSize=${test.tradeSize}`, async () => {
        const { callVault, caller, base, quote, receiver } = await loadFixture(
          vaultSetup,
        );
        // create a deposit and check that totalAssets and totalSupply amounts are computed correctly
        await addMockDeposit(callVault, test.deposit, base, quote);
        let startTime = await latest();
        let t0 = startTime + 7 * ONE_DAY;
        expect(await callVault.totalAssets()).to.eq(
          parseEther(test.deposit.toString()),
        );
        expect(await callVault.totalSupply()).to.eq(
          parseEther(test.deposit.toString()),
        );
        // mock vault
        await callVault.increaseTotalLockedSpread(
          parseEther(test.totalLockedSpread.toString()),
        );
        await callVault.setMaxMaturity(t0);
        if (test.tradeSize > 0) {
          const infos = [
            {
              maturity: t0,
              strikes: [500].map((el) => parseEther(el.toString())),
              sizes: [1].map((el) => parseEther(el.toString())),
            },
          ];
          await callVault.setListingsAndSizes(infos);
          await callVault.increaseTotalLockedAssets(parseEther('1'));
        }
        console.log('test');
        let pps: number = parseFloat(
          formatEther(await callVault.getPricePerShare()),
        );
        expect(pps).to.be.closeTo(test.expected, 0.00000001);
      });
    });
  });

  describe('#_getSpotPrice', () => {
    it('should get the current spot price', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      vault = callVault;

      let spot = parseFloat(formatEther(await callVault['getSpotPrice()']()));
      expect(spot).to.eq(1500);
    });

    it('should get the spot price at a particular timestamp', async () => {
      const currentTime = 1878113571;
      const t0 = currentTime + 7 * ONE_DAY;
      const t1 = currentTime + 10 * ONE_DAY;

      const { callVault, oracleAdapter, base, quote } = await loadFixture(
        vaultSetup,
      );
      vault = callVault;

      await oracleAdapter.mock.quoteFrom
        .withArgs(base.address, quote.address, t0)
        .returns(parseUnits('1000', 18));
      await oracleAdapter.mock.quoteFrom
        .withArgs(base.address, quote.address, t1)
        .returns(parseUnits('1400', 18));

      let spot = parseFloat(
        formatEther(await callVault['getSpotPrice(uint256)'](t0)),
      );
      expect(spot).to.eq(1000);

      spot = parseFloat(
        formatEther(await callVault['getSpotPrice(uint256)'](t1)),
      );
      expect(spot).to.eq(1400);
    });
  });

  describe('#_getMaturityAfterTimestamp', () => {
    before(async () => {
      const { callVault } = await loadFixture(vaultSetup);
      vault = callVault;
    });
    it('works for maturities with length 0', async () => {
      await expect(
        vault.getMaturityAfterTimestamp('50000'),
      ).to.be.revertedWithCustomError(vault, 'Vault__GreaterThanMaxMaturity');
    });

    it('works for maturities with length greater than 1', async () => {
      const infos = [
        {
          maturity: '100000',
          strikes: [],
          sizes: [],
        },
      ];
      await vault.setListingsAndSizes(infos);

      expect(infos[0]['maturity']).to.eq(
        await vault.getMaturityAfterTimestamp('50000'),
      );

      await vault.clearListingsAndSizes();
    });

    it('works for maturities with length greater than 1', async () => {
      const infos = [
        {
          maturity: '100000',
          strikes: [],
          sizes: [],
        },
        {
          maturity: '200000',
          strikes: [],
          sizes: [],
        },
        {
          maturity: '300000',
          strikes: [],
          sizes: [],
        },
      ];
      await vault.setListingsAndSizes(infos);

      expect(infos[0]['maturity']).to.eq(
        await vault.getMaturityAfterTimestamp('50000'),
      );
      expect(infos[1]['maturity']).to.eq(
        await vault.getMaturityAfterTimestamp('150000'),
      );
      expect(infos[2]['maturity']).to.eq(
        await vault.getMaturityAfterTimestamp('250000'),
      );

      await vault.clearListingsAndSizes();
    });
  });

  describe('#_getNumberOfUnexpiredListings', () => {
    let startTime = 100000;

    t0 = startTime + 7 * ONE_DAY;
    t1 = startTime + 10 * ONE_DAY;
    t2 = startTime + 14 * ONE_DAY;
    t3 = startTime + 30 * ONE_DAY;

    let vault: UnderwriterVaultMock;

    async function setup() {
      const { callVault } = await loadFixture(vaultSetup);
      vault = callVault;

      const infos = [
        {
          maturity: t0,
          strikes: [500, 1000, 1500, 2000].map((el) =>
            parseEther(el.toString()),
          ),
          sizes: [1, 1, 1, 1].map((el) => parseEther(el.toString())),
        },
        {
          maturity: t1,
          strikes: [1000, 1500, 2000].map((el) => parseEther(el.toString())),
          sizes: [1, 1, 1].map((el) => parseEther(el.toString())),
        },
        {
          maturity: t2,
          strikes: [1000, 1500, 2000].map((el) => parseEther(el.toString())),
          sizes: [1, 1, 1].map((el) => parseEther(el.toString())),
        },
        {
          maturity: 2 * t2,
          strikes: [1200, 1500].map((el) => parseEther(el.toString())),
          sizes: [1, 1].map((el) => parseEther(el.toString())),
        },
      ];
      await vault.setListingsAndSizes(infos);
    }

    let tests = [
      { timestamp: t0 - ONE_DAY, expected: 12 },
      { timestamp: t0, expected: 8 },
      { timestamp: t0 + ONE_DAY, expected: 8 },
      { timestamp: t2 + ONE_DAY, expected: 2 },
      { timestamp: t3, expected: 0 },
      { timestamp: t3 + ONE_DAY, expected: 0 },
    ];

    tests.forEach(async (test) => {
      it(`returns ${test.expected} when timestamp=${test.timestamp}`, async () => {
        await loadFixture(setup);
        let result = await vault.getNumberOfUnexpiredListings(test.timestamp);

        expect(result).to.eq(test.expected);
      });
    });

    it('returns 0 when there are no existing listings', async () => {
      await vault.clearListingsAndSizes();

      let result = await vault.getNumberOfUnexpiredListings(t0 - ONE_DAY);
      let expected = 0;

      expect(result).to.eq(expected);
    });
  });
});
