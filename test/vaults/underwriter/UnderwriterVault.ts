import { expect } from 'chai';
import { ethers } from 'hardhat';
import {
  latest,
  ONE_DAY,
  ONE_HOUR,
  ONE_WEEK,
  increaseTo,
} from '../../../utils/time';
import {
  parseEther,
  parseUnits,
  formatEther,
  formatUnits,
} from 'ethers/lib/utils';
import {
  addMockDeposit,
  vaultSetup,
  createPool,
  increaseTotalAssets,
  increaseTotalShares,
  maturity,
  oracleAdapter,
  p,
  callVaultProxy,
} from './VaultSetup';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { UnderwriterVaultMock, ERC20Mock } from '../../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

import { IPoolMock__factory } from '../../../typechain';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { TokenType } from '../../../utils/sdk/types';
import { getValidMaturity } from '../../../utils/time';
import { BigNumberish, BigNumber } from 'ethers';

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

export async function setMaturities(vault: UnderwriterVaultMock) {
  startTime = await latest();
  spot = 2800;
  minMaturity = startTime + 10 * ONE_DAY;
  maxMaturity = startTime + 20 * ONE_DAY;

  const infos = [
    {
      maturity: minMaturity.toString(),
      strikes: [],
      sizes: [],
    },
    {
      maturity: maxMaturity.toString(),
      strikes: [],
      sizes: [],
    },
  ];
  await vault.setListingsAndSizes(infos);
}

describe('UnderwriterVault', () => {
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

  describe('#_getTotalLiabilitiesExpired', () => {
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

    let tests = [
      { isCall: true, timestamp: t0 - ONE_DAY, expected: 0 },
      { isCall: false, timestamp: t0 - ONE_DAY, expected: 0 },
      { isCall: true, timestamp: t0, expected: 0.4 },
      { isCall: false, timestamp: t0, expected: 2000 },
      { isCall: true, timestamp: t0 + ONE_DAY, expected: 0.4 },
      { isCall: false, timestamp: t0 + ONE_DAY, expected: 2000 },
      { isCall: true, timestamp: t1, expected: 0.4 + 2.28571428571 },
      { isCall: false, timestamp: t1, expected: 2000 + 100 },
      { isCall: true, timestamp: t1 + ONE_DAY, expected: 0.4 + 2.28571428571 },
      { isCall: false, timestamp: t1 + ONE_DAY, expected: 2000 + 100 },
      {
        isCall: true,
        timestamp: t2 + ONE_DAY,
        expected: 2.68571428571 + 0.625,
      },
      { isCall: false, timestamp: t2 + ONE_DAY, expected: 2100 + 400 },
      { isCall: true, timestamp: t3, expected: 2.68571428571 + 0.625 + 0.2 },
      { isCall: false, timestamp: t3, expected: 2100 + 400 + 1000 },
      {
        isCall: true,
        timestamp: t3 + ONE_DAY,
        expected: 2.68571428571 + 0.625 + 0.2,
      },
      { isCall: false, timestamp: t3 + ONE_DAY, expected: 2100 + 400 + 1000 },
    ];

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

  describe('#_getTotalLiabilitiesUnexpired', () => {
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

    let tests = [
      { isCall: true, timestamp: t0 - ONE_DAY, expected: 1.697282885495867 },
      { isCall: false, timestamp: t0 - ONE_DAY, expected: 5597.282885495868 },
      { isCall: true, timestamp: t0, expected: 1.2853079354050814 },
      { isCall: false, timestamp: t0, expected: 3585.3079354050824 },
      { isCall: true, timestamp: t0 + ONE_DAY, expected: 1.2755281851488665 },
      { isCall: false, timestamp: t0 + ONE_DAY, expected: 3575.528185148866 },
      { isCall: true, timestamp: t2 + ONE_DAY, expected: 0.24420148996961677 },
      { isCall: false, timestamp: t2 + ONE_DAY, expected: 1044.2014899696167 },
      { isCall: true, timestamp: t3, expected: 0 },
      { isCall: false, timestamp: t3, expected: 0 },
      { isCall: true, timestamp: t3 + ONE_DAY, expected: 0 },
      { isCall: false, timestamp: t3 + ONE_DAY, expected: 0 },
    ];

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

      let result = await vault.getTotalLiabilitiesUnexpired(t0 - ONE_DAY, spot);
      let expected = 0;

      expect(result).to.eq(parseEther(expected.toString()));

      await vault.setIsCall(false);

      result = await vault.getTotalLiabilitiesUnexpired(t0 - ONE_DAY, spot);
      expected = 0;

      expect(result).to.eq(parseEther(expected.toString()));
    });
  });

  describe('#_getTotalLiabilities', () => {
    const currentTime = 1878113571;
    const t0 = currentTime + 7 * ONE_DAY;
    const t1 = currentTime + 10 * ONE_DAY;
    const t2 = currentTime + 14 * ONE_DAY;
    const t3 = currentTime + 30 * ONE_DAY;

    let vault: UnderwriterVaultMock;

    const infos = [
      {
        maturity: t0,
        strikes: [800, 900, 1500, 2000].map((el) => parseEther(el.toString())),
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

    let tests = [
      { isCall: true, timestamp: t0 - ONE_DAY, expected: 5.37163 },
      { isCall: false, timestamp: t0 - ONE_DAY, expected: 1457.45 },
      { isCall: true, timestamp: t0, expected: 4.45834 },
      { isCall: false, timestamp: t0, expected: 2887.51 },
      { isCall: true, timestamp: t0 + ONE_DAY, expected: 4.44419 },
      { isCall: false, timestamp: t0 + ONE_DAY, expected: 2866.29 },
      { isCall: true, timestamp: t1, expected: 4.15323 },
      { isCall: false, timestamp: t1, expected: 2901.27 },
      { isCall: true, timestamp: t1 + ONE_DAY, expected: 4.14161 },
      { isCall: false, timestamp: t1 + ONE_DAY, expected: 2883.85 },
      { isCall: true, timestamp: t2 + ONE_DAY, expected: 4.22983 },
      { isCall: false, timestamp: t2 + ONE_DAY, expected: 2678.67948 },
      { isCall: true, timestamp: t3, expected: 3.51071 },
      { isCall: false, timestamp: t3, expected: 3500 },
      { isCall: true, timestamp: t3 + ONE_DAY, expected: 3.51071 },
      { isCall: false, timestamp: t3 + ONE_DAY, expected: 3500 },
    ];

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

  describe('#_getTotalFairValue', () => {
    const currentTime = 1878113571;
    const t0 = currentTime + 7 * ONE_DAY;
    const t1 = currentTime + 10 * ONE_DAY;
    const t2 = currentTime + 14 * ONE_DAY;
    const t3 = currentTime + 30 * ONE_DAY;

    let vault: UnderwriterVaultMock;

    const infos = [
      {
        maturity: t0,
        strikes: [800, 900, 1500, 2000].map((el) => parseEther(el.toString())),
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

    let tests = [
      {
        isCall: true,
        timestamp: t0 - ONE_DAY,
        expected: totalLockedCall - 5.37163,
      },
      {
        isCall: false,
        timestamp: t0 - ONE_DAY,
        expected: totalLockedPut - 1457.45,
      },
      { isCall: true, timestamp: t0, expected: totalLockedCall - 4.45834 },
      { isCall: false, timestamp: t0, expected: totalLockedPut - 2887.51 },
      {
        isCall: true,
        timestamp: t0 + ONE_DAY,
        expected: totalLockedCall - 4.44419,
      },
      {
        isCall: false,
        timestamp: t0 + ONE_DAY,
        expected: totalLockedPut - 2866.29,
      },
      { isCall: true, timestamp: t1, expected: totalLockedCall - 4.15323 },
      { isCall: false, timestamp: t1, expected: totalLockedPut - 2901.27 },
      {
        isCall: true,
        timestamp: t1 + ONE_DAY,
        expected: totalLockedCall - 4.14161,
      },
      {
        isCall: false,
        timestamp: t1 + ONE_DAY,
        expected: totalLockedPut - 2883.85,
      },
      {
        isCall: true,
        timestamp: t2 + ONE_DAY,
        expected: totalLockedCall - 4.22983,
      },
      {
        isCall: false,
        timestamp: t2 + ONE_DAY,
        expected: totalLockedPut - 2678.67948,
      },
      { isCall: true, timestamp: t3, expected: totalLockedCall - 3.51071 },
      { isCall: false, timestamp: t3, expected: totalLockedPut - 3500 },
      {
        isCall: true,
        timestamp: t3 + ONE_DAY,
        expected: totalLockedCall - 3.51071,
      },
      {
        isCall: false,
        timestamp: t3 + ONE_DAY,
        expected: totalLockedPut - 3500,
      },
    ];

    tests.forEach(async (test) => {
      let totalLocked = test.isCall ? totalLockedCall : totalLockedPut;

      it(`returns ${test.expected} when isCall=${test.isCall} and timestamp=${test.timestamp}`, async () => {
        await vault.setIsCall(test.isCall);
        await vault.setTotalLockedAssets(parseEther(totalLocked.toString()));

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

  describe('#_addListing', () => {
    let startTime = 100000;

    let t0 = startTime + 7 * ONE_DAY;
    let t1 = startTime + 10 * ONE_DAY;
    let t2 = startTime + 14 * ONE_DAY;

    before(async () => {
      const { callVault } = await loadFixture(vaultSetup);
      vault = callVault;
    });

    it('adds a listing when there are no listings', async () => {
      let strike = parseEther('1000');
      let maturity = t1;

      let n = await vault.getNumberOfListings();
      expect(n).to.eq(0);

      await vault.addListing(strike, maturity);

      let c = await vault.contains(strike, maturity);

      expect(c).to.be.true;

      n = await vault.getNumberOfListings();
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(1);
      expect(minMaturity).to.eq(t1);
      expect(maxMaturity).to.eq(t1);
    });

    it('adds a listing to an existing maturity', async () => {
      let n = await vault.getNumberOfListings();
      expect(n).to.eq(1);

      let strike = parseEther('2000');
      let maturity = t1;

      await vault.addListing(strike, maturity);

      let c = await vault.contains(strike, maturity);

      expect(c).to.be.true;

      n = await vault.getNumberOfListings();
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(2);
      expect(minMaturity).to.eq(t1);
      expect(maxMaturity).to.eq(t1);
    });

    it('adds a listing with a maturity before minMaturity', async () => {
      let n = await vault.getNumberOfListings();
      expect(n).to.eq(2);

      let strike = parseEther('1000');
      let maturity = t0;

      await vault.addListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.true;

      n = await vault.getNumberOfListings();
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(3);
      expect(minMaturity).to.eq(t0);
      expect(maxMaturity).to.eq(t1);
    });

    it('adds a listing with a maturity after maxMaturity', async () => {
      let n = await vault.getNumberOfListings();
      expect(n).to.eq(3);

      let strike = parseEther('1000');
      let maturity = t2;

      await vault.addListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.true;

      n = await vault.getNumberOfListings();
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(4);
      expect(minMaturity).to.eq(t0);
      expect(maxMaturity).to.eq(t2);
    });

    it('will not add a duplicate listing', async () => {
      let n = await vault.getNumberOfListings();
      expect(n).to.eq(4);

      let strike = parseEther('1000');
      let maturity = t2;

      await vault.addListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.true;

      n = await vault.getNumberOfListings();
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(4);
      expect(minMaturity).to.eq(t0);
      expect(maxMaturity).to.eq(t2);
    });
  });

  describe('#_removeListing', () => {
    startTime = 100000;

    t0 = startTime + 7 * ONE_DAY;
    t1 = startTime + 10 * ONE_DAY;
    t2 = startTime + 14 * ONE_DAY;

    before(async () => {
      const { callVault } = await loadFixture(vaultSetup);
      vault = callVault;

      const infos = [
        {
          maturity: t0,
          strikes: [1000, 2000].map((el) => parseEther(el.toString())),
          sizes: [0, 0].map((el) => parseEther(el.toString())),
        },
        {
          maturity: t1,
          strikes: [1000, 2000].map((el) => parseEther(el.toString())),
          sizes: [0, 0].map((el) => parseEther(el.toString())),
        },
        {
          maturity: t2,
          strikes: [1000].map((el) => parseEther(el.toString())),
          sizes: [0].map((el) => parseEther(el.toString())),
        },
      ];
      await vault.setListingsAndSizes(infos);
    });

    it('should adjust and remove maxMaturity when it becomes empty', async () => {
      let strike = parseEther('1000');
      let maturity = t2;

      let n = await vault.getNumberOfListings();
      expect(n).to.eq(5);

      await vault.removeListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.false;

      n = await vault.getNumberOfListingsOnMaturity(maturity);
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(0);
      expect(minMaturity).to.eq(t0);
      expect(maxMaturity).to.eq(t1);
    });

    it('should remove strike from minMaturity', async () => {
      let strike = parseEther('1000');
      let maturity = t0;

      let n = await vault.getNumberOfListings();
      expect(n).to.eq(4);

      await vault.removeListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.false;

      n = await vault.getNumberOfListingsOnMaturity(maturity);
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(1);
      expect(minMaturity).to.eq(t0);
      expect(maxMaturity).to.eq(t1);
    });

    it('should adjust and remove minMaturity when it becomes empty', async () => {
      let strike = parseEther('2000');
      let maturity = t0;

      let n = await vault.getNumberOfListings();
      expect(n).to.eq(3);

      await vault.removeListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.false;

      n = await vault.getNumberOfListingsOnMaturity(maturity);
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(0);
      expect(minMaturity).to.eq(t1);
      expect(maxMaturity).to.eq(t1);
    });

    it('should remove strike from single maturity', async () => {
      let strike = parseEther('1000');
      let maturity = t1;

      let n = await vault.getNumberOfListings();
      expect(n).to.eq(2);

      await vault.removeListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.false;

      n = await vault.getNumberOfListingsOnMaturity(maturity);
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(1);
      expect(minMaturity).to.eq(t1);
      expect(maxMaturity).to.eq(t1);
    });

    it('should remove strike from last maturity and leave 0 listings', async () => {
      let strike = parseEther('2000');
      let maturity = t1;

      let n = await vault.getNumberOfListings();
      expect(n).to.eq(1);

      await vault.removeListing(strike, maturity);

      let c = await vault.contains(strike, maturity);
      expect(c).to.be.false;

      n = await vault.getNumberOfListingsOnMaturity(maturity);
      let minMaturity = await vault.getMinMaturity();
      let maxMaturity = await vault.getMaxMaturity();

      expect(n).to.eq(0);
      expect(await vault.getNumberOfListings()).to.eq(0);
      expect(minMaturity).to.eq(0);
      expect(maxMaturity).to.eq(0);
    });
  });

  describe('#convertToShares', () => {
    it('if no shares have been minted, minted shares should equal deposited assets', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      const assetAmount = parseEther('2');
      const shareAmount = await callVault.convertToShares(assetAmount);
      expect(shareAmount).to.eq(assetAmount);
    });

    it('if supply is non-zero and pricePerShare is one, minted shares equals the deposited assets', async () => {
      const { callVault, caller, base, quote, receiver } = await loadFixture(
        vaultSetup,
      );
      await setMaturities(callVault);
      await addMockDeposit(callVault, 8, base, quote);
      const assetAmount = parseEther('2');
      const shareAmount = await callVault.convertToShares(assetAmount);
      expect(shareAmount).to.eq(assetAmount);
    });

    it('if supply is non-zero, minted shares equals the deposited assets adjusted by the pricePerShare', async () => {
      const { callVault, caller, base, quote, receiver } = await loadFixture(
        vaultSetup,
      );
      let assetAmount: any = 2;
      await setMaturities(callVault);
      await addMockDeposit(callVault, 2, base, quote);
      await callVault.increaseTotalLockedSpread(parseEther('1.0'));
      assetAmount = parseEther(assetAmount.toString());
      const shareAmount = await callVault.convertToShares(assetAmount);
      expect(shareAmount).to.eq(parseEther('4'));
    });
  });

  describe('#convertToAssets', () => {
    it('if total supply is zero, revert due to zero shares', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      const shareAmount = parseEther('2');
      await expect(
        callVault.convertToAssets(shareAmount),
      ).to.be.revertedWithCustomError(callVault, 'Vault__ZeroShares');
    });

    it('if supply is non-zero and pricePerShare is one, withdrawn assets equals share amount', async () => {
      const { callVault, base, quote, caller, receiver } = await loadFixture(
        vaultSetup,
      );
      await setMaturities(callVault);
      await addMockDeposit(callVault, 2, base, quote);
      const shareAmount = parseEther('2');
      const assetAmount = await callVault.convertToAssets(shareAmount);
      expect(shareAmount).to.eq(assetAmount);
    });

    it('if supply is non-zero and pricePerShare is 0.5, withdrawn assets equals half the share amount', async () => {
      const { callVault, base, quote, caller, receiver } = await loadFixture(
        vaultSetup,
      );
      await setMaturities(callVault);
      await addMockDeposit(callVault, 2, base, quote);
      await callVault.increaseTotalLockedSpread(parseEther('1.0'));
      const shareAmount = 2;
      const assetAmount = await callVault.convertToAssets(
        parseEther(shareAmount.toString()),
      );
      expect(parseFloat(formatEther(assetAmount))).to.eq(0.5 * shareAmount);
    });
  });

  describe('#_availableAssets', () => {
    // availableAssets = totalAssets - totalLockedSpread - lockedAssets
    // totalAssets = totalDeposits + premiums + spread - exercise
    before(async () => {
      const { callVault, caller, receiver, base, quote } = await loadFixture(
        vaultSetup,
      );
      vault = callVault;
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

  describe('#getPricePerShare', () => {
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

  describe('#maxWithdraw', () => {
    it('maxWithdraw should revert for a zero address', async () => {
      const { callVault, caller, receiver, base, quote } = await loadFixture(
        vaultSetup,
      );
      await setMaturities(callVault);
      await addMockDeposit(callVault, 2, base, quote);
      await expect(
        callVault.maxWithdraw(ethers.constants.AddressZero),
      ).to.be.revertedWithCustomError(callVault, 'Vault__AddressZero');
    });

    it('maxWithdraw should return the available assets for a non-zero address', async () => {
      const { callVault, caller, deployer, receiver, base, quote } =
        await loadFixture(vaultSetup);
      await setMaturities(callVault);
      await addMockDeposit(callVault, 3, base, quote, 3, receiver.address);
      await callVault.increaseTotalLockedSpread(parseEther('0.1'));
      await callVault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = await callVault.maxWithdraw(receiver.address);

      expect(assetAmount).to.eq(parseEther('2.4'));
    });

    it('maxWithdraw should return the assets the receiver owns', async () => {
      const { callVault, caller, receiver, base, quote } = await loadFixture(
        vaultSetup,
      );
      await setMaturities(callVault);
      await addMockDeposit(callVault, 8, base, quote, 8, caller.address);
      await addMockDeposit(callVault, 2, base, quote, 2, receiver.address);
      await callVault.increaseTotalLockedSpread(parseEther('0.0'));
      await callVault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = await callVault.maxWithdraw(receiver.address);
      expect(assetAmount).to.eq(parseEther('2'));
    });

    it('maxWithdraw should return the assets the receiver owns since there are sufficient funds', async () => {
      const { callVault, caller, receiver, base, quote } = await loadFixture(
        vaultSetup,
      );
      await setMaturities(callVault);
      await addMockDeposit(callVault, 7, base, quote, 7, caller.address);
      await addMockDeposit(callVault, 2, base, quote, 2, receiver.address);
      await callVault.increaseTotalLockedSpread(parseEther('0.1'));
      await callVault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = parseFloat(
        formatEther(await callVault.maxWithdraw(receiver.address)),
      );
      expect(assetAmount).to.be.closeTo(1.977777777777777, 0.00000001);
    });
  });

  describe('#maxRedeem', () => {
    it('maxRedeem should revert for a zero address', async () => {
      const { callVault, caller, receiver, base, quote } = await loadFixture(
        vaultSetup,
      );
      await setMaturities(callVault);
      await addMockDeposit(callVault, 2, base, quote, 2, receiver.address);
      await expect(
        callVault.maxRedeem(ethers.constants.AddressZero),
      ).to.be.revertedWithCustomError(callVault, 'Vault__AddressZero');
    });

    it('maxRedeem should return the amount of shares that are redeemable', async () => {
      const { callVault, caller, receiver, base, quote } = await loadFixture(
        vaultSetup,
      );
      await setMaturities(callVault);
      await addMockDeposit(callVault, 3, base, quote, 3, receiver.address);
      await callVault.increaseTotalLockedSpread(parseEther('0.1'));
      await callVault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = await callVault.maxRedeem(receiver.address);
      expect(assetAmount).to.eq('2482758620689655174');
    });
  });

  describe('#previewMint', () => {
    it('previewMint should return amount of assets required to mint the amount of shares', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      await setMaturities(callVault);
      const assetAmount = await callVault.previewMint(parseEther('2.1'));
      expect(assetAmount).to.eq(parseEther('2.1'));
    });

    it('previewMint should return amount of assets required to mint', async () => {
      const { callVault, caller, receiver, base, quote } = await loadFixture(
        vaultSetup,
      );
      await setMaturities(callVault);
      await addMockDeposit(callVault, 2, base, quote);
      await callVault.increaseTotalLockedSpread(parseEther('0.2'));
      const assetAmount = await callVault.previewMint(parseEther('4'));
      expect(assetAmount).to.eq(parseEther('3.6'));
    });
  });

  describe('#afterBuy', () => {
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

      await callVault.afterBuy(
        minMaturity,
        parseEther(premium.toString()),
        maturity - startTime,
        parseEther(size.toString()),
        parseEther(spread.toString()),
        parseEther(strike.toString()),
      );
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

  describe('#settleMaturity', () => {
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

  describe('#asset', () => {
    it('returns base asset for callVault', async () => {
      const { callVault, base } = await loadFixture(vaultSetup);
      const asset = await callVault.asset();
      expect(asset).to.eq(base.address);
    });
    it('returns quote asset for putVault', async () => {
      const { putVault, quote } = await loadFixture(vaultSetup);
      const asset = await putVault.asset();
      expect(asset).to.eq(quote.address);
    });
  });

  describe('#contains', () => {
    let vault: UnderwriterVaultMock;
    beforeEach(async () => {
      const { callVault } = await loadFixture(vaultSetup);
      vault = callVault;
      const infos = [
        {
          maturity: 100000,
          strikes: [parseEther('1234')],
          sizes: [1],
        },
      ];
      await callVault.setListingsAndSizes(infos);
    });

    it('vault expected to contain strike 1234 and maturity 100000', async () => {
      expect(await vault.contains(parseEther('1234'), 100000)).to.eq(true);
    });
    it('vault expected not to contain strike 1200 and maturity 100000', async () => {
      expect(await vault.contains(parseEther('1200'), 100000)).to.eq(false);
    });
    it('vault expected not to contain strike 1234 and maturity 10000', async () => {
      expect(await vault.contains(parseEther('1200'), 10000)).to.eq(false);
    });
  });

  describe('#vaultSetup', () => {
    // TODO: what does this test?
    it('returns addressZero from factory non existing pool', async () => {
      const { base, quote, maturity, oracleAdapter, p } = await loadFixture(
        vaultSetup,
      );
      for (const isCall of [true, false]) {
        const nonExistingPoolKey = {
          base: base.address,
          quote: quote.address,
          oracleAdapter: oracleAdapter.address,
          strike: parseEther('500'), // ATM,
          maturity: BigNumber.from(maturity),
          isCallPool: isCall,
        };
        const listingAddr = await p.poolFactory.getPoolAddress(
          nonExistingPoolKey,
        );
        expect(listingAddr).to.be.eq(ethers.constants.AddressZero);
      }
    });

    it('returns the proper pool address from factory', async () => {
      const { p, callPoolKey, callPool } = await loadFixture(vaultSetup);
      const listingAddr = await p.poolFactory.getPoolAddress(callPoolKey);
      expect(listingAddr).to.be.eq(callPool.address);
    });

    it('gets a valid iv value via vault', async () => {
      const { volOracle, base } = await loadFixture(vaultSetup);
      const spot = parseEther('1500');
      const strike = parseEther('1500'); // ATM
      const maturity = parseEther('0.03835616'); // 2 weeks
      const iv = await volOracle[
        'getVolatility(address,uint256,uint256,uint256)'
      ](base.address, spot, strike, maturity);

      expect(parseFloat(formatEther(iv))).to.be.eq(0.7340403881444237);
    });

    it('responds to mock oracle adapter query', async () => {
      const { oracleAdapter, base, quote } = await loadFixture(vaultSetup);
      const price = await oracleAdapter.quote(base.address, quote.address);
      expect(parseFloat(formatUnits(price, 18))).to.eq(1500);
    });

    it('test correct initialisation of the vaults storage variables', async () => {
      const { callVault, lastTimeStamp } = await loadFixture(vaultSetup);

      let minClevel: BigNumberish;
      let maxClevel: BigNumberish;
      let alphaClevel: BigNumberish;
      let hourlyDecayDiscount: BigNumberish;
      let minDTE: BigNumberish;
      let maxDTE: BigNumberish;
      let minDelta: BigNumberish;
      let maxDelta: BigNumberish;
      let _lastTradeTimestamp: BigNumberish;

      [minClevel, maxClevel, alphaClevel, hourlyDecayDiscount] =
        await callVault.getClevelParams();

      expect(parseFloat(formatEther(minClevel))).to.eq(1.0);
      expect(parseFloat(formatEther(maxClevel))).to.eq(1.2);
      expect(parseFloat(formatEther(alphaClevel))).to.eq(3.0);
      expect(parseFloat(formatEther(hourlyDecayDiscount))).to.eq(0.005);

      [minDTE, maxDTE, minDelta, maxDelta] = await callVault.getTradeBounds();

      expect(parseFloat(formatEther(minDTE))).to.eq(3.0);
      expect(parseFloat(formatEther(maxDTE))).to.eq(30.0);
      expect(parseFloat(formatEther(minDelta))).to.eq(0.1);
      expect(parseFloat(formatEther(maxDelta))).to.eq(0.7);

      _lastTradeTimestamp = await callVault.getLastTradeTimestamp();
      // check that a timestamp was set
      expect(_lastTradeTimestamp).to.eq(lastTimeStamp);
      // check timestamp is in seconds epoch
      expect(_lastTradeTimestamp.toString().length).to.eq(10);
    });

    it('should properly initialize a new option pool', async () => {
      const { p, callPoolKey, callPool } = await loadFixture(vaultSetup);
      expect(await p.poolFactory.getPoolAddress(callPoolKey)).to.eq(
        callPool.address,
      );
    });

    it('should properly hydrate accounts with funds', async () => {
      const { base, quote, deployer, caller, receiver, underwriter, trader } =
        await loadFixture(vaultSetup);
      expect(await base.balanceOf(deployer.address)).to.equal(
        parseEther('1000'),
      );
      expect(await base.balanceOf(caller.address)).to.equal(parseEther('1000'));
      expect(await base.balanceOf(receiver.address)).to.equal(
        parseEther('1000'),
      );
      expect(await base.balanceOf(underwriter.address)).to.equal(
        parseEther('1000'),
      );
      expect(await base.balanceOf(trader.address)).to.equal(parseEther('1000'));

      expect(await quote.balanceOf(deployer.address)).to.equal(
        parseEther('1000000'),
      );
      expect(await quote.balanceOf(caller.address)).to.equal(
        parseEther('1000000'),
      );
      expect(await quote.balanceOf(receiver.address)).to.equal(
        parseEther('1000000'),
      );
      expect(await quote.balanceOf(underwriter.address)).to.equal(
        parseEther('1000000'),
      );
      expect(await quote.balanceOf(trader.address)).to.equal(
        parseEther('1000000'),
      );
    });
    it('retrieves valid option delta', async () => {
      const { callVault, putVault, base, volOracle } = await loadFixture(
        vaultSetup,
      );
      const spotPrice = await callVault['getSpotPrice()']();
      const strike = parseEther('1500');
      const tau = parseEther('0.03835616'); // 14 DTE
      const rfRate = await volOracle.getRiskFreeRate();
      const sigma = await volOracle[
        'getVolatility(address,uint256,uint256,uint256)'
      ](base.address, spotPrice, strike, tau);
      const callDelta = await callVault.getDelta(
        spotPrice,
        strike,
        tau,
        sigma,
        rfRate,
        true,
      );

      const putDelta = await putVault.getDelta(
        spotPrice,
        strike,
        tau,
        sigma,
        rfRate,
        false,
      );

      expect(parseFloat(formatEther(callDelta))).to.approximately(0.528, 0.001);
      expect(parseFloat(formatEther(putDelta))).to.approximately(-0.471, 0.001);
    });

    describe('#minting options from pool', () => {
      it('allows writeFrom to mint call options when directly called', async () => {
        const { underwriter, trader, base, callPool, p } = await loadFixture(
          vaultSetup,
        );
        const size = parseEther('5');
        const callPoolUnderwriter = IPoolMock__factory.connect(
          callPool.address,
          underwriter,
        );
        const fee = await callPool.takerFee(size, 0, true);
        const totalSize = size.add(fee);
        await base.connect(underwriter).approve(p.router.address, totalSize);
        await callPoolUnderwriter.writeFrom(
          underwriter.address,
          trader.address,
          size,
        );
        expect(await base.balanceOf(callPool.address)).to.eq(totalSize);
        expect(await callPool.balanceOf(trader.address, TokenType.LONG)).to.eq(
          size,
        );
        expect(await callPool.balanceOf(trader.address, TokenType.SHORT)).to.eq(
          0,
        );
        expect(
          await callPool.balanceOf(underwriter.address, TokenType.LONG),
        ).to.eq(0);
        expect(
          await callPool.balanceOf(underwriter.address, TokenType.SHORT),
        ).to.eq(size);
      });

      it('allows writeFrom to mint put options when directly called', async () => {
        const { underwriter, trader, quote, putPool } = await loadFixture(
          vaultSetup,
        );
        const size = parseEther('5');
        const strike = 1500;
        const putPoolUnderwriter = IPoolMock__factory.connect(
          putPool.address,
          underwriter,
        );
        const fee = await putPool.takerFee(size, 0, false);
        const totalSize = size.mul(strike).add(fee);
        console.log(totalSize);
        await quote.connect(underwriter).approve(p.router.address, totalSize);
        await putPoolUnderwriter.writeFrom(
          underwriter.address,
          trader.address,
          size,
        );
        expect(await quote.balanceOf(putPool.address)).to.eq(totalSize);
        expect(await putPool.balanceOf(trader.address, TokenType.LONG)).to.eq(
          size,
        );
        expect(await putPool.balanceOf(trader.address, TokenType.SHORT)).to.eq(
          0,
        );
        expect(
          await putPool.balanceOf(underwriter.address, TokenType.LONG),
        ).to.eq(0);
        expect(
          await putPool.balanceOf(underwriter.address, TokenType.SHORT),
        ).to.eq(size);
      });

      it('allows the vault to mint call options for the LP and Trader', async () => {
        const { callVault, lp, trader, base, quote, callPool } =
          await loadFixture(vaultSetup);
        const lpDepositSize = 5; // units of base
        const lpDepositSizeBN = parseEther(lpDepositSize.toString());
        await addMockDeposit(callVault, lpDepositSize, base, quote);
        const strike = parseEther('1500');
        const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
        const tradeSize = parseEther('2');

        const [, premium, mintingFee, , spread] = await callVault.quote(
          strike,
          maturity,
          tradeSize,
        );

        const totalTransfer = premium.add(mintingFee).add(spread);

        await base.connect(trader).approve(callVault.address, totalTransfer);
        await callVault.connect(trader).buy(strike, maturity, tradeSize);
        const vaultCollateralBalance = lpDepositSizeBN
          .sub(tradeSize)
          .add(premium)
          .add(spread);

        // todo: cover the put case
        // collateral
        expect(await base.balanceOf(callPool.address)).to.eq(
          tradeSize.add(mintingFee),
        );

        expect(await callPool.balanceOf(trader.address, TokenType.LONG)).to.eq(
          tradeSize,
        );
        expect(
          await callPool.balanceOf(callVault.address, TokenType.SHORT),
        ).to.eq(tradeSize);
        // as time passes the B-Sch. price and C-level change
        expect(
          parseFloat(formatEther(await base.balanceOf(callVault.address))),
        ).to.be.closeTo(
          parseFloat(formatEther(vaultCollateralBalance)),
          0.000001,
        );
      });

      it('allows the vault to mint put options for the LP and Trader', async () => {
        const { putVault, lp, trader, base, quote, putPool } =
          await loadFixture(vaultSetup);

        const strike = 1500;
        const lpDepositSize = 5 * strike; // 5 units
        const lpDepositSizeBN = parseUnits(lpDepositSize.toString(), 6);
        await addMockDeposit(putVault, lpDepositSize, base, quote);

        const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
        const tradeSize = parseEther('2');
        const fee = await putPool.takerFee(tradeSize, 0, false);
        const totalSize = tradeSize.add(fee);
        const strikeBN = parseEther(strike.toString());
        // FIXME: these tests will not run because writeFrom decimalization for puts is incorrect

        // await putVault.connect(trader).buy(strikeBN, maturity, tradeSize);
        // const vaultCollateralBalance = lpDepositSizeBN.sub(totalSize);

        // expect(await quote.balanceOf(putPool.address)).to.eq(totalSize);
        // expect(await putPool.balanceOf(trader.address, TokenType.LONG)).to.eq(
        //   tradeSize,
        // );
        // expect(await putPool.balanceOf(putVault.address, TokenType.SHORT)).to.eq(
        //   tradeSize,
        // );
        // expect(await quote.balanceOf(putVault.address)).to.be.eq(
        //   vaultCollateralBalance,
        // );
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

  describe('#_ensureSupportedListing', () => {
    const tests = [
      // todo: hydrate delta values closer to bounds
      {
        spot: '1000',
        strike: '1200',
        tau: '0.007945205479452055', // 2.9 DTE
        rfRate: '0.01',
        sigma: '0.823',
        error: 'Vault__MaturityBounds',
        message: 'dte is less than minDTE',
      },
      {
        spot: '1000',
        strike: '1200',
        tau: '0.07671232876712329', // 28 DTE
        rfRate: '0.01',
        sigma: '0.823',
        error: null,
        message: 'dte is within bounds',
      },
      {
        spot: '1000',
        strike: '1200',
        tau: '0.1232876712328767', // 45 DTE
        rfRate: '0.01',
        sigma: '0.823',
        error: 'Vault__MaturityBounds',
        message: 'dte is greater than maxMaturity',
      },
      {
        spot: '1000',
        strike: '4000',
        tau: '0.07671232876712329', // 28 DTE
        rfRate: '0.01',
        sigma: '0.823',
        error: 'Vault__DeltaBounds',
        message: 'delta is less than minDelta',
      },
      {
        spot: '1000',
        strike: '1100',
        tau: '0.0136986301369863', // 5 DTE
        rfRate: '0.01',
        sigma: '0.823',
        error: null,
        message: 'delta is within bounds',
      },
      {
        spot: '5000',
        strike: '1200',
        tau: '0.0136986301369863', // 5 DTE
        rfRate: '0.01',
        sigma: '0.823',
        error: 'Vault__DeltaBounds',
        message: 'delta is greater than maxDelta',
      },
    ];

    tests.forEach(async (test) => {
      if (test.error != null) {
        it(`should raise ${test.error} error when ${test.message}`, async () => {
          const { callVault } = await loadFixture(vaultSetup);
          await expect(
            callVault.ensureSupportedListing(
              parseEther(test.spot),
              parseEther(test.strike),
              parseEther(test.tau),
              parseEther(test.sigma),
              parseEther(test.rfRate),
            ),
          ).to.be.revertedWithCustomError(callVault, test.error);
        });
      } else {
        it(`should not raise an error when ${test.message}`, async () => {
          const { callVault } = await loadFixture(vaultSetup);
          await expect(
            callVault.ensureSupportedListing(
              parseEther(test.spot),
              parseEther(test.strike),
              parseEther(test.tau),
              parseEther(test.sigma),
              parseEther(test.rfRate),
            ),
          );
          expect(true);
        });
      }
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

    describe('#buy', () => {
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
        await callVault.connect(trader).buy(strike, maturity, tradeSize);
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
        await callVault.connect(trader).buy(strike, maturity, tradeSize);

        await expect(
          callVault.connect(trader).buy(strike, maturity, tradeSize),
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
        await callVault.connect(trader).buy(strike, maturity, tradeSize);

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

        await callVault.connect(trader).buy(strike, maturity, tradeSize);
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
