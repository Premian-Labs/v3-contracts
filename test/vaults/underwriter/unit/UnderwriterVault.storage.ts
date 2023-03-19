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

let t0: number;
let t1: number;
let t2: number;
let t3: number;

describe('UnderwriterVaultStorage', () => {
  describe('#getMaturityAfterTimestamp', () => {
    before(async () => {
      const { callVault } = await loadFixture(vaultSetup);
      vault = callVault;
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

  describe('#getNumberOfUnexpiredListings', () => {
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

  describe('#addListing', () => {
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

  describe('#removeListing', () => {
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
});
