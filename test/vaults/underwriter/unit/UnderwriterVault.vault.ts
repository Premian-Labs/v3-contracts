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
  describe('#_computeCLevel', () => {
    let tests = [
      {
        utilisation: 0,
        duration: 0,
        expected: 1,
      },
      {
        utilisation: 0.2,
        duration: 3,
        expected: 1,
      },
      {
        utilisation: 0.4,
        duration: 6,
        expected: 1,
      },
      {
        utilisation: 0.6,
        duration: 9,
        expected: 1.0079159591866442,
      },
      {
        utilisation: 0.8,
        duration: 12,
        expected: 1.0450342615036845,
      },
      {
        utilisation: 1,
        duration: 15,
        expected: 1.125,
      },
    ];

    tests.forEach(async (test) => {
      it(`should have cLevel=${test.expected} when utilisation=${test.utilisation} and hoursSinceLastTrade=${test.duration}`, async () => {
        const { callVault } = await loadFixture(vaultSetup);
        vault = callVault;

        let cLevelBN = await callVault.computeCLevel(
          parseEther(test.utilisation.toString()),
          parseEther(test.duration.toString()),
          parseEther('3'),
          parseEther('1.0'),
          parseEther('1.2'),
          parseEther('0.005'),
        );
        let cLevel = parseFloat(formatEther(cLevelBN));

        expect(cLevel).to.be.equal(test.expected);
      });
    });
  });

  describe('#_getTradeQuote', () => {
    it('reverts on no strike input', async () => {
      const { base, quote, callVault } = await loadFixture(vaultSetup);

      const lastTradeTimestamp = 500000000;
      await callVault.setLastTradeTimestamp(lastTradeTimestamp);

      const timestamp = 1000000000;
      const spot = parseEther('2000');
      const strike = parseEther('1500'); // ATM
      const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));

      const quoteSize = parseEther('4.9999');
      const depositSize = 5; // units of base
      await addMockDeposit(callVault, depositSize, base, quote);

      const output = await callVault.getTradeQuoteInternal(
        timestamp,
        spot,
        strike,
        maturity,
        true,
        quoteSize,
        true,
      );
      console.log(parseFloat(formatEther(output.price)));
    });

    it('reverts on expired maturity input', async () => {});

    it('should revert due to too large incoming trade size', async () => {});

    it('returns proper quote parameters: price, mintingFee, cLevel', async () => {});

    it('reverts if maxCLevel is not set properly', async () => {});

    it('reverts if the C level alpha is not set properly', async () => {});
  });

  describe('#trade', () => {});
});
