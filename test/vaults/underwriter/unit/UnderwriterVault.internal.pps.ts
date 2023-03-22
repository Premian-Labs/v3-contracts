import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import {
  addMockDeposit,
  createPool,
  increaseTotalAssets,
  oracleAdapter,
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
import { MockContract } from '@ethereum-waffle/mock-contract';

let startTime: number;

let t0: number;
let t1: number;
let t2: number;
let t3: number;

let vault: UnderwriterVaultMock;

describe('UnderwriterVault.internal.pps', () => {
  describe('#_getTotalLiabilitiesExpired', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        let startTime = 100000;

        t0 = startTime + 7 * ONE_DAY;
        t1 = startTime + 10 * ONE_DAY;
        t2 = startTime + 14 * ONE_DAY;
        t3 = startTime + 30 * ONE_DAY;

        before(async () => {
          const { callVault, oracleAdapter, volOracle, base, quote } =
            await loadFixture(vaultSetup);
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

  startTime = 100000;

  t0 = startTime + 7 * ONE_DAY;
  t1 = startTime + 10 * ONE_DAY;
  t2 = startTime + 14 * ONE_DAY;
  t3 = startTime + 30 * ONE_DAY;

  const infos = [
    {
      maturity: t0,
      strikes: [900, 2000].map((el) => parseEther(el.toString())),
      sizes: [1, 2].map((el) => parseEther(el.toString())),
    },
    {
      maturity: t1,
      strikes: [700, 1500].map((el) => parseEther(el.toString())),
      sizes: [1, 5].map((el) => parseEther(el.toString())),
    },
    {
      maturity: t2,
      strikes: [800, 2000].map((el) => parseEther(el.toString())),
      sizes: [1, 1].map((el) => parseEther(el.toString())),
    },
    {
      maturity: t3,
      strikes: [1500].map((el) => parseEther(el.toString())),
      sizes: [2].map((el) => parseEther(el.toString())),
    },
  ];

  async function setupVolOracleMock(volOracle: MockContract, base: ERC20Mock) {
    // timestamp: t0 - ONE_DAY. (Done)
    await volOracle.mock.getVolatility
      .withArgs(
        base.address,
        parseEther('1000'),
        [
          parseEther('900'),
          parseEther('2000'),
          parseEther('700'),
          parseEther('1500'),
          parseEther('800'),
          parseEther('2000'),
          parseEther('1500'),
        ],
        [
          '2739726027397260',
          '2739726027397260',
          '10958904109589041',
          '10958904109589041',
          '21917808219178082',
          '21917808219178082',
          '65753424657534246',
        ],
      )
      .returns([
        parseEther('0.123'),
        parseEther('0.89'),
        parseEther('3.5'),
        parseEther('0.034'),
        parseEther('2.1'),
        parseEther('1.1'),
        parseEther('0.99'),
      ]);

    // timestamp: t0 (Done)
    await volOracle.mock.getVolatility
      .withArgs(
        base.address,
        parseEther('1000'),
        [
          parseEther('700'),
          parseEther('1500'),
          parseEther('800'),
          parseEther('2000'),
          parseEther('1500'),
        ],
        [
          '5479452054794520',
          '5479452054794520',
          '16438356164383561',
          '16438356164383561',
          '60273972602739726',
        ],
      )
      .returns([
        parseEther('0.512'),
        parseEther('0.034'),
        parseEther('2.1'),
        parseEther('1.2'),
        parseEther('0.9'),
      ]);

    // timestamp: t0 + ONE_DAY (Done)
    await volOracle.mock.getVolatility
      .withArgs(
        base.address,
        parseEther('1000'),
        [
          parseEther('700'),
          parseEther('1500'),
          parseEther('800'),
          parseEther('2000'),
          parseEther('1500'),
        ],
        [
          '8219178082191780',
          '8219178082191780',
          '19178082191780821',
          '19178082191780821',
          '63013698630136986',
        ],
      )
      .returns([
        parseEther('0.512'),
        parseEther('0.034'),
        parseEther('2.1'),
        parseEther('1.2'),
        parseEther('0.9'),
      ]);

    // timestamp: t1
    await volOracle.mock.getVolatility
      .withArgs(
        base.address,
        parseEther('1000'),
        [parseEther('800'), parseEther('2000'), parseEther('1500')],
        ['10958904109589041', '10958904109589041', '54794520547945205'],
      )
      .returns([parseEther('1.1'), parseEther('1.2'), parseEther('0.9')]);

    // timestamp: t1 + ONE_DAY (needs fixing)
    await volOracle.mock.getVolatility
      .withArgs(
        base.address,
        parseEther('1000'),
        [parseEther('800'), parseEther('2000'), parseEther('1500')],
        ['8219178082191780', '8219178082191780', '52054794520547945'],
      )
      .returns([parseEther('0.512'), parseEther('0.034'), parseEther('0.9')]);

    // timestamp: t2 + ONE_DAY (needs fixing)
    await volOracle.mock.getVolatility
      .withArgs(
        base.address,
        parseEther('1000'),
        [parseEther('1500')],
        ['41095890410958904'],
      )
      .returns([parseEther('0.2')]);

    return infos;
  }

  describe('#_getTotalLiabilitiesUnexpired', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        let spot = parseEther('1000');

        before(async () => {
          const { callVault, volOracle, base } = await loadFixture(vaultSetup);
          vault = callVault;
          await setupVolOracleMock(volOracle, base);
          await vault.setListingsAndSizes(infos);
        });

        let callTests = [
          { isCall: true, timestamp: t0 - ONE_DAY, expected: 0.679618 },
          { isCall: true, timestamp: t0, expected: 0.541099 },
          { isCall: true, timestamp: t0 + ONE_DAY, expected: 0.534583 },
          { isCall: true, timestamp: t2 + ONE_DAY, expected: 0 },
          { isCall: true, timestamp: t3, expected: 0 },
          { isCall: true, timestamp: t3 + ONE_DAY, expected: 0 },
        ];

        let putTests = [
          { isCall: false, timestamp: t0 - ONE_DAY, expected: 6576.0 },
          { isCall: false, timestamp: t0, expected: 4537.998 },
          { isCall: false, timestamp: t0 + ONE_DAY, expected: 4531.865 },
          { isCall: false, timestamp: t2 + ONE_DAY, expected: 998.767 },
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
            let delta = test.isCall ? 0.000002 : 0.002;
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
        let vault: UnderwriterVaultMock;

        before(async () => {
          const { callVault, putVault, oracleAdapter, volOracle, base, quote } =
            await loadFixture(vaultSetup);
          await oracleAdapter.mock.quote.returns(parseUnits('1000', 18));
          vault = isCall ? callVault : putVault;
          await setupVolOracleMock(volOracle, base);
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
          { isCall: true, timestamp: t0 - ONE_DAY, expected: 0.679618 },
          { isCall: true, timestamp: t0, expected: 0.641099 },
          { isCall: true, timestamp: t0 + ONE_DAY, expected: 0.634583 },
          { isCall: true, timestamp: t1, expected: 0.806477 },
          { isCall: true, timestamp: t1 + ONE_DAY, expected: 0.804646 },
          { isCall: true, timestamp: t2 + ONE_DAY, expected: 1.1 },
          { isCall: true, timestamp: t3, expected: 1.1 },
          { isCall: true, timestamp: t3 + ONE_DAY, expected: 1.1 },
        ];

        let putTests = [
          { isCall: false, timestamp: t0 - ONE_DAY, expected: 6576.0 },
          { isCall: false, timestamp: t0, expected: 6537.998 },
          { isCall: false, timestamp: t0 + ONE_DAY, expected: 6531.865 },
          { isCall: false, timestamp: t1, expected: 4504.526 },
          { isCall: false, timestamp: t1 + ONE_DAY, expected: 4502.855 },
          { isCall: false, timestamp: t2 + ONE_DAY, expected: 3898.767 },
          { isCall: false, timestamp: t3, expected: 3900 },
          { isCall: false, timestamp: t3 + ONE_DAY, expected: 3900 },
        ];

        let tests = isCall ? callTests : putTests;

        tests.forEach(async (test) => {
          it(`returns ${test.expected} when isCall=${test.isCall} and timestamp=${test.timestamp}`, async () => {
            await vault.setIsCall(test.isCall);
            let result = await vault.getTotalLiabilities(test.timestamp);
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
        let vault: UnderwriterVaultMock;

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
          const { callVault, oracleAdapter, volOracle, base, quote } =
            await loadFixture(vaultSetup);
          vault = callVault;
          await oracleAdapter.mock.quote.returns(parseUnits('1000', 18));
          await setupVolOracleMock(volOracle, base);

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
            expected: totalLockedCall - 0.679618,
          },
          { isCall: true, timestamp: t0, expected: totalLockedCall - 0.641099 },
          {
            isCall: true,
            timestamp: t0 + ONE_DAY,
            expected: totalLockedCall - 0.634583,
          },
          { isCall: true, timestamp: t1, expected: totalLockedCall - 0.806477 },
          {
            isCall: true,
            timestamp: t1 + ONE_DAY,
            expected: totalLockedCall - 0.804646,
          },
          {
            isCall: true,
            timestamp: t2 + ONE_DAY,
            expected: totalLockedCall - 1.1,
          },
          { isCall: true, timestamp: t3, expected: totalLockedCall - 1.1 },
          {
            isCall: true,
            timestamp: t3 + ONE_DAY,
            expected: totalLockedCall - 1.1,
          },
        ];

        let putTests = [
          {
            isCall: false,
            timestamp: t0 - ONE_DAY,
            expected: totalLockedPut - 6576.0,
          },
          { isCall: false, timestamp: t0, expected: totalLockedPut - 6537.998 },
          {
            isCall: false,
            timestamp: t0 + ONE_DAY,
            expected: totalLockedPut - 6531.865,
          },
          { isCall: false, timestamp: t1, expected: totalLockedPut - 4504.526 },
          {
            isCall: false,
            timestamp: t1 + ONE_DAY,
            expected: totalLockedPut - 4502.855,
          },
          {
            isCall: false,
            timestamp: t2 + ONE_DAY,
            expected: totalLockedPut - 3898.767,
          },
          { isCall: false, timestamp: t3, expected: totalLockedPut - 3900 },
          {
            isCall: false,
            timestamp: t3 + ONE_DAY,
            expected: totalLockedPut - 3900,
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
            let result = await vault.getTotalFairValue(test.timestamp);
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
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        let callTests = [
          { expected: 1, deposit: 2, tls: 0, tradeSize: 0 },
          { expected: 0.9, deposit: 2, tls: 0.2, tradeSize: 0 },
          { expected: 0.98, deposit: 5, tls: 0.1, tradeSize: 0 },
          { expected: 0.749874, deposit: 2, tls: 0.2, tradeSize: 1.5 },
          { expected: 0.899916, deposit: 2, tls: 0, tradeSize: 1 },
        ];
        let putTests = [
          { expected: 1, deposit: 2, tls: 0, tradeSize: 0 },
          { expected: 0.9, deposit: 2, tls: 0.2, tradeSize: 0 },
          { expected: 0.98, deposit: 5, tls: 0.1, tradeSize: 0 },
          { expected: 0.884747, deposit: 2, tls: 0.2, tradeSize: 1.5 },
          { expected: 0.989831, deposit: 2, tls: 0, tradeSize: 1 },
        ];
        let tests = isCall ? callTests : putTests;
        tests.forEach(async (test) => {
          it(`returns ${test.expected} when totalLockedSpread=${test.tls} and tradeSize=${test.tradeSize}`, async () => {
            const { callVault, putVault, volOracle, base, quote } =
              await loadFixture(vaultSetup);
            vault = isCall ? callVault : putVault;
            const token = isCall ? base : quote;

            await volOracle.mock.getVolatility
              .withArgs(base.address, parseEther('1500'), [], [])
              .returns([]);

            // create a deposit and check that totalAssets and totalSupply amounts are computed correctly
            await addMockDeposit(vault, test.deposit, base, quote);
            let startTime = await latest();
            let t0 = startTime + 7 * ONE_DAY;
            await volOracle.mock.getVolatility
              .withArgs(
                base.address,
                parseEther('1500'),
                [parseEther('1200')],
                ['19177923642820903'],
              )
              .returns([parseEther('0.51')]);
            expect(await vault.totalAssets()).to.eq(
              parseUnits(test.deposit.toString(), await token.decimals()),
            );
            expect(await vault.totalSupply()).to.eq(
              parseEther(test.deposit.toString()),
            );
            // mock vault
            await vault.increaseTotalLockedSpread(
              parseEther(test.tls.toString()),
            );
            await vault.setMaxMaturity(t0);
            if (test.tradeSize > 0) {
              // increase total locked assets
              const infos = [
                {
                  maturity: t0,
                  strikes: [1200].map((el) => parseEther(el.toString())),
                  sizes: [test.tradeSize].map((el) =>
                    parseEther(el.toString()),
                  ),
                },
              ];
              await vault.setListingsAndSizes(infos);
              await vault.increaseTotalLockedAssets(
                parseEther(test.tradeSize.toString()),
              );
            }
            let pps: number = parseFloat(
              formatEther(await vault.getPricePerShare()),
            );
            expect(pps).to.be.closeTo(test.expected, 0.000002);
          });
        });
      });
    }
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
});
