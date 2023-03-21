import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import {
  addMockDeposit,
  base,
  createPool,
  increaseTotalAssets,
  oracleAdapter,
  poolKey,
  quote,
  trader,
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
import {
  ERC20Mock,
  IPoolMock,
  UnderwriterVaultMock,
} from '../../../../typechain';
import { BigNumber } from 'ethers';
import { setMaturities } from '../VaultSetup';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { MockContract } from '@ethereum-waffle/mock-contract';
import { PoolUtil } from '../../../../utils/PoolUtil';
import { PoolKey } from '../../../../utils/sdk/types';

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
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        let vault: UnderwriterVaultMock;
        async function setup() {
          const {
            base,
            quote,
            callVault,
            putVault,
            volOracle,
            oracleAdapter,
            deployer,
            p,
          } = await loadFixture(vaultSetup);

          vault = isCall ? callVault : putVault;
          const spot = parseEther('1000');
          const xstrike = 1100;
          const strike = parseEther('1100'); // ATM
          const timestamp = await getValidMaturity(2, 'weeks');
          const maturity = await getValidMaturity(3, 'weeks');

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

          const lastTradeTimestamp = timestamp - 3 * ONE_HOUR;
          await vault.setLastTradeTimestamp(lastTradeTimestamp);

          await oracleAdapter.mock.quote.returns(spot);
          await volOracle.mock['getVolatility(address,uint256,uint256,uint256)']
            .withArgs(base.address, spot, strike, '19178082191780821')
            .returns(parseEther('1.54'));

          const depositSize = isCall ? 5 : 5 * xstrike;
          await addMockDeposit(vault, depositSize, base, quote);

          return { vault, maturity, spot, strike, timestamp };
        }

        it('should process valid quote correctly', async () => {
          const { vault, maturity, spot, strike, timestamp } =
            await loadFixture(setup);

          const quoteSize = parseEther('3');

          const output = await vault.getTradeQuoteInternal(
            timestamp,
            spot,
            strike,
            maturity,
            isCall,
            quoteSize,
            true,
          );
          const totalPremium = parseFloat(formatEther(output.price));
          const expectedPremium = isCall
            ? 0.15828885563446596
            : 473.3029052286404;
          const delta = isCall ? 1e-6 : 1e-2;
          expect(totalPremium).to.be.closeTo(expectedPremium, delta);
        });

        it('reverts on pool not existing', async () => {
          const { vault, spot, strike } = await loadFixture(setup);
          const timestamp = await getValidMaturity(2, 'weeks');
          const maturity = await getValidMaturity(4, 'weeks');

          await expect(
            vault.getTradeQuoteInternal(
              timestamp,
              spot,
              strike,
              maturity,
              isCall,
              parseEther('3'),
              true,
            ),
          ).to.be.revertedWithCustomError(vault, 'Vault__OptionPoolNotListed');
        });

        it('reverts on zero strike', async () => {
          const { vault, maturity, spot, strike, timestamp } =
            await loadFixture(setup);

          const quoteSize = parseEther('3');

          await expect(
            vault.getTradeQuoteInternal(
              timestamp,
              spot,
              parseEther('0'),
              maturity,
              isCall,
              quoteSize,
              true,
            ),
          ).to.be.revertedWithCustomError(vault, 'Vault__StrikeZero');
        });

        it('reverts on trying to buy a put with the call vault or a put with the call vault', async () => {
          const { vault, maturity, spot, strike, timestamp } =
            await loadFixture(setup);

          const quoteSize = parseEther('3');

          await expect(
            vault.getTradeQuoteInternal(
              timestamp,
              spot,
              strike,
              maturity,
              !isCall,
              quoteSize,
              true,
            ),
          ).to.be.revertedWithCustomError(
            vault,
            'Vault__OptionTypeMismatchWithVault',
          );
        });

        it('reverts on trying to sell to the vault', async () => {
          const { vault, maturity, spot, strike, timestamp } =
            await loadFixture(setup);

          const quoteSize = parseEther('3');

          await expect(
            vault.getTradeQuoteInternal(
              timestamp,
              spot,
              strike,
              maturity,
              isCall,
              quoteSize,
              false,
            ),
          ).to.be.revertedWithCustomError(vault, 'Vault__TradeMustBeBuy');
        });

        it('reverts on trying to buy an option that is expired', async () => {
          const { vault, maturity, spot, strike, timestamp } =
            await loadFixture(setup);

          const quoteSize = parseEther('3');

          await expect(
            vault.getTradeQuoteInternal(
              maturity + 3 * ONE_HOUR,
              spot,
              strike,
              maturity,
              isCall,
              quoteSize,
              true,
            ),
          ).to.be.revertedWithCustomError(vault, 'Vault__OptionExpired');
        });

        it('reverts on trying to buy an option is not within the DTE bounds', async () => {
          const {
            base,
            quote,
            callVault,
            putVault,
            volOracle,
            oracleAdapter,
            deployer,
            p,
          } = await loadFixture(vaultSetup);

          vault = isCall ? callVault : putVault;
          const spot = parseEther('1000');
          const xstrike = 1100;
          const strike = parseEther('1100'); // ATM
          const timestamp = await getValidMaturity(1, 'weeks');

          // TODO: extend this maturity to be farther out without `Invalid Maturity Parameters` being thrown
          const maturity = await getValidMaturity(4, 'weeks');

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

          const lastTradeTimestamp = timestamp - 3 * ONE_HOUR;
          await vault.setLastTradeTimestamp(lastTradeTimestamp);

          await oracleAdapter.mock.quote.returns(spot);
          await volOracle.mock['getVolatility(address,uint256,uint256,uint256)']
            .withArgs(base.address, spot, strike, '57534246575342465')
            .returns(parseEther('1.54'));

          const depositSize = isCall ? 5 : 5 * xstrike;
          await addMockDeposit(vault, depositSize, base, quote);

          const quoteSize = parseEther('3');

          await expect(
            vault.getTradeQuoteInternal(
              timestamp,
              spot,
              strike,
              maturity,
              isCall,
              quoteSize,
              true,
            ),
          ).to.be.revertedWithCustomError(vault, 'Vault__OutOfTradeBounds');
        });
      });
    }
  });

  describe('#trade', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        let vault: UnderwriterVaultMock;
        async function setup() {
          const {
            trader,
            base,
            quote,
            callVault,
            putVault,
            volOracle,
            oracleAdapter,
            deployer,
            p,
          } = await loadFixture(vaultSetup);

          vault = isCall ? callVault : putVault;
          const spot = parseEther('1000');
          const xstrike = 1100;
          const strike = parseEther('1100'); // ATM
          const timestamp = await getValidMaturity(2, 'weeks');
          const maturity = await getValidMaturity(3, 'weeks');

          const values = await createPool(
            strike,
            maturity,
            isCall,
            deployer,
            base,
            quote,
            oracleAdapter,
            p,
          );
          const pool = values[0];

          const lastTradeTimestamp = timestamp - 3 * ONE_HOUR;
          await vault.setLastTradeTimestamp(lastTradeTimestamp);

          await oracleAdapter.mock.quote.returns(spot);
          await volOracle.mock['getVolatility(address,uint256,uint256,uint256)']
            .withArgs(base.address, spot, strike, '19178082191780821')
            .returns(parseEther('1.54'));

          const depositSize = isCall ? 5 : 5 * xstrike;
          await addMockDeposit(vault, depositSize, base, quote);

          return {
            pool,
            trader,
            vault,
            maturity,
            spot,
            strike,
            timestamp,
            base,
            quote,
          };
        }

        it('should process trade', async () => {
          const {
            pool,
            trader,
            vault,
            maturity,
            spot,
            strike,
            timestamp,
            base,
            quote,
          } = await loadFixture(setup);

          const quoteSize = parseEther('3');

          // TODO: Fix allowance issue so trade can function
          const token = isCall ? base : quote;
          await token
            .connect(trader)
            .approve(vault.address, parseEther('1000'));

          await vault
            .connect(trader)
            .tradeInternal(
              timestamp,
              spot,
              strike,
              maturity,
              isCall,
              quoteSize,
              true,
            );
        });
      });
    }
  });
});
