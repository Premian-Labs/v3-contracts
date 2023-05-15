import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  addDeposit,
  base,
  createPool,
  poolKey,
  quote,
  vaultSetup,
} from '../UnderwriterVault.fixture';
import {
  formatEther,
  formatUnits,
  parseEther,
  parseUnits,
} from 'ethers/lib/utils';
import { expect } from 'chai';
import { getValidMaturity, ONE_HOUR } from '../../../../utils/time';
import { UnderwriterVaultMock } from '../../../../typechain';
import { TokenType } from '../../../../utils/sdk/types';
import { ethers } from 'ethers';

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

  describe('#getQuote', () => {
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
            lp,
            p,
            optionMath,
          } = await loadFixture(vaultSetup);

          vault = isCall ? callVault : putVault;
          const spot = parseEther('1000');
          const xstrike = 1100;
          const strike = parseEther('1100'); // ATM
          const timestamp = await getValidMaturity(2, 'weeks');
          const maturity = await getValidMaturity(3, 'weeks');

          const { poolKey } = await createPool(
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
          await addDeposit(vault, lp, depositSize, base, quote);

          return {
            base,
            quote,
            vault,
            maturity,
            spot,
            strike,
            timestamp,
            poolKey,
          };
        }

        it('should process valid quote correctly', async () => {
          const { poolKey, base, quote, vault, spot, timestamp } =
            await loadFixture(setup);

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          const quoteSize = parseEther('3');

          const premium = await vault.getQuote(poolKey, quoteSize, true);
          const token = isCall ? base : quote;
          const totalPremium = parseFloat(
            formatUnits(premium, await token.decimals()),
          );
          const expectedPremium = isCall
            ? 0.15828885563446596
            : 469.9068335343156;
          const delta = isCall ? 1e-6 : 1e-2;
          expect(totalPremium).to.be.closeTo(expectedPremium, delta);
        });

        it('should revert if there is not enough available assets', async () => {
          const { poolKey, vault, spot, timestamp } = await loadFixture(setup);

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          await expect(
            vault.getQuote(poolKey, parseEther('6'), true),
          ).to.be.revertedWithCustomError(vault, 'Vault__InsufficientFunds');
        });

        it('should revert on pool not existing', async () => {
          const { poolKey, vault, spot } = await loadFixture(setup);
          const timestamp = await getValidMaturity(2, 'weeks');
          const maturity = await getValidMaturity(4, 'weeks');

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          await expect(
            vault.getQuote({ ...poolKey, maturity }, parseEther('3'), true),
          ).to.be.revertedWithCustomError(vault, 'Vault__OptionPoolNotListed');
        });

        it('should revert on zero size', async () => {
          const { poolKey, vault, maturity, spot, strike, timestamp } =
            await loadFixture(setup);

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          const quoteSize = parseEther('0');

          await expect(
            vault.getQuote(poolKey, quoteSize, true),
          ).to.be.revertedWithCustomError(vault, 'Vault__ZeroSize');
        });

        it('should revert on zero strike', async () => {
          const { poolKey, vault, maturity, spot, strike, timestamp } =
            await loadFixture(setup);

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          const quoteSize = parseEther('3');

          await expect(
            vault.getQuote({ ...poolKey, strike: 0 }, quoteSize, true),
          ).to.be.revertedWithCustomError(vault, 'Vault__StrikeZero');
        });

        it('should revert on trying to buy a put with the call vault or a put with the call vault', async () => {
          const { poolKey, vault, spot, timestamp } = await loadFixture(setup);

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          const quoteSize = parseEther('3');

          await expect(
            vault.getQuote(
              { ...poolKey, isCallPool: !poolKey.isCallPool },
              quoteSize,
              true,
            ),
          ).to.be.revertedWithCustomError(
            vault,
            'Vault__OptionTypeMismatchWithVault',
          );
        });

        it('should revert on trying to sell to the vault', async () => {
          const { poolKey, vault, spot, timestamp } = await loadFixture(setup);

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          const quoteSize = parseEther('3');

          await expect(
            vault.getQuote(poolKey, quoteSize, false),
          ).to.be.revertedWithCustomError(vault, 'Vault__TradeMustBeBuy');
        });

        it('should revert on trying to buy an option that is expired', async () => {
          const { poolKey, vault, maturity, spot } = await loadFixture(setup);

          await vault.setTimestamp(maturity + 3 * ONE_HOUR);
          await vault.setSpotPrice(spot);

          const quoteSize = parseEther('3');

          await expect(
            vault.getQuote(poolKey, quoteSize, true),
          ).to.be.revertedWithCustomError(vault, 'Vault__OptionExpired');
        });

        it('should revert on trying to buy an option not within the DTE bounds', async () => {
          const {
            base,
            quote,
            callVault,
            putVault,
            volOracle,
            oracleAdapter,
            deployer,
            lp,
            p,
          } = await loadFixture(vaultSetup);

          vault = isCall ? callVault : putVault;
          const spot = parseEther('1000');
          const xstrike = 1100;
          const strike = parseEther('1100');
          const timestamp = await getValidMaturity(1, 'weeks');
          const maturity = await getValidMaturity(2, 'months');

          await volOracle.mock['getVolatility(address,uint256,uint256,uint256)']
            .withArgs(
              base.address,
              spot,
              parseEther(xstrike.toString()),
              '153424657534246575',
            )
            .returns(parseEther('0.51'));

          const { poolKey } = await createPool(
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
            .withArgs(base.address, spot, strike, '191780821917808219')
            .returns(parseEther('1.54'));
          await volOracle.mock['getVolatility(address,uint256,uint256,uint256)']
            .withArgs(base.address, spot, strike, '134246575342465753')
            .returns(parseEther('1.54'));

          const depositSize = isCall ? 5 : 5 * xstrike;
          await addDeposit(vault, lp, depositSize, base, quote);

          const quoteSize = parseEther('3');

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          await expect(
            vault.getQuote(poolKey, quoteSize, true),
          ).to.be.revertedWithCustomError(vault, 'Vault__OutOfDTEBounds');
        });

        it('should revert on trying to buy an option not within the delta bounds', async () => {
          const {
            base,
            quote,
            callVault,
            putVault,
            volOracle,
            oracleAdapter,
            deployer,
            lp,
            p,
          } = await loadFixture(vaultSetup);

          vault = isCall ? callVault : putVault;
          const spot = parseEther('1000');
          const xstrike = 1500;
          const strike = parseEther('1500'); // ATM
          const timestamp = await getValidMaturity(2, 'weeks');
          const maturity = await getValidMaturity(3, 'weeks');

          const { poolKey } = await createPool(
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
          await addDeposit(vault, lp, depositSize, base, quote);

          const quoteSize = parseEther('3');

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          await expect(
            vault.getQuote(poolKey, quoteSize, true),
          ).to.be.revertedWithCustomError(vault, 'Vault__OutOfDeltaBounds');
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
            lp,
            p,
            optionMath,
          } = await loadFixture(vaultSetup);

          vault = isCall ? callVault : putVault;
          const spot = parseEther('1000');
          const xstrike = 1100;
          const strike = parseEther('1100'); // ATM
          const timestamp = await getValidMaturity(2, 'weeks');
          const maturity = await getValidMaturity(3, 'weeks');

          const { pool, poolKey } = await createPool(
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
          await volOracle.mock['getVolatility(address,uint256,uint256,uint256)']
            .withArgs(base.address, spot, strike, '134246575342465753')
            .returns(parseEther('1.54'));

          const depositSize = isCall ? 5 : 5 * xstrike;
          await addDeposit(vault, lp, depositSize, base, quote);

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
            optionMath,
            poolKey,
          };
        }

        it('should process valid trade correctly', async () => {
          const {
            poolKey,
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

          const tradeSize = parseEther('3');

          // Check that the premium has been transferred
          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          const totalPremium = await vault.getQuote(poolKey, tradeSize, true);

          // Approve amount for trader to trade with
          const token = isCall ? base : quote;
          await token
            .connect(trader)
            .approve(vault.address, parseEther('1000'));

          expect(
            await vault
              .connect(trader)
              .trade(poolKey, tradeSize, true, parseEther('1000')),
          )
            .to.emit(vault, 'UpdateQuotes')
            .to.emit(vault, 'Trade');

          // Get deposit size and collateral in right format
          const _strike = 1100;
          const depositSize = parseUnits(
            (isCall ? 5 : 5 * _strike).toString(),
            await token.decimals(),
          );
          const collateral = parseUnits(
            (isCall ? 3 : 3 * _strike).toString(),
            await token.decimals(),
          );

          // Get minting fee
          const mintingFee = await pool.takerFee(
            ethers.constants.AddressZero,
            tradeSize,
            0,
            false,
          );

          // Check that long contracts have been transferred to trader
          const longs = await pool.balanceOf(trader.address, TokenType.LONG);
          expect(longs).to.eq(tradeSize);

          // Check that short contracts have been transferred to vault
          const shorts = await pool.balanceOf(vault.address, TokenType.SHORT);
          expect(shorts).to.eq(tradeSize);

          // Check that premium has been transferred to vault
          const vaultBalance = await token.balanceOf(vault.address);
          expect(vaultBalance).to.be.eq(
            depositSize.add(totalPremium).sub(collateral).sub(mintingFee),
          );

          // Check that listing has been successfully added to vault
          const positionSize = await vault.getPositionSize(strike, maturity);
          expect(positionSize).to.be.eq(tradeSize);

          // Check that collateral and minting fee have been transferred to pool
          const poolBalance = await token.balanceOf(pool.address);
          expect(poolBalance).to.be.eq(collateral.add(mintingFee));
        });

        it('should revert on not having enough available capital', async () => {
          const { poolKey, vault, trader, spot, timestamp } = await loadFixture(
            setup,
          );

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          // Approve amount for trader to trade with
          const token = isCall ? base : quote;
          await token
            .connect(trader)
            .approve(vault.address, parseEther('1000'));

          const tradeSize = parseEther('6');

          await expect(
            vault
              .connect(trader)
              .trade(poolKey, tradeSize, true, parseEther('1000')),
          ).to.be.revertedWithCustomError(vault, 'Vault__InsufficientFunds');
        });

        it('should revert on being above allowed slippage', async () => {
          const { poolKey, trader, vault, spot, timestamp, base, quote } =
            await loadFixture(setup);

          const tradeSize = parseEther('3');

          // Check that the premium has been transferred
          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          const totalPremium = await vault.getQuote(poolKey, tradeSize, true);

          // Approve amount for trader to trade with
          const token = isCall ? base : quote;
          await token
            .connect(trader)
            .approve(vault.address, parseEther('1000'));

          const multiplier = parseUnits('0.5', await token.decimals());

          expect(
            await vault
              .connect(trader)
              .trade(poolKey, tradeSize, true, totalPremium.mul(multiplier)),
          ).to.be.revertedWithCustomError(vault, 'Vault__AboveMaxSlippage');
        });

        it('should revert on pool not existing', async () => {
          const { poolKey, vault, trader, spot } = await loadFixture(setup);
          const timestamp = await getValidMaturity(2, 'weeks');
          const maturity = await getValidMaturity(4, 'weeks');

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          // Approve amount for trader to trade with
          const token = isCall ? base : quote;
          await token
            .connect(trader)
            .approve(vault.address, parseEther('1000'));

          const tradeSize = parseEther('3');

          await expect(
            vault
              .connect(trader)
              .trade(
                { ...poolKey, maturity },
                tradeSize,
                true,
                parseEther('1000'),
              ),
          ).to.be.revertedWithCustomError(vault, 'Vault__OptionPoolNotListed');
        });

        it('should revert on zero size', async () => {
          const { vault, trader, maturity, spot, strike, timestamp } =
            await loadFixture(setup);

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          const tradeSize = parseEther('0');

          await expect(
            vault
              .connect(trader)
              .trade(poolKey, tradeSize, true, parseEther('1000')),
          ).to.be.revertedWithCustomError(vault, 'Vault__ZeroSize');
        });

        it('should revert on zero strike', async () => {
          const { poolKey, vault, trader, spot, timestamp } = await loadFixture(
            setup,
          );

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          const tradeSize = parseEther('3');

          await expect(
            vault
              .connect(trader)
              .trade(
                { ...poolKey, strike: 0 },
                tradeSize,
                true,
                parseEther('1000'),
              ),
          ).to.be.revertedWithCustomError(vault, 'Vault__StrikeZero');
        });

        it('should revert on trying to buy a put with the call vault or a put with the call vault', async () => {
          const { poolKey, vault, trader, spot, timestamp } = await loadFixture(
            setup,
          );

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          const tradeSize = parseEther('3');

          await expect(
            vault
              .connect(trader)
              .trade(
                { ...poolKey, isCallPool: !poolKey.isCallPool },
                tradeSize,
                true,
                parseEther('1000'),
              ),
          ).to.be.revertedWithCustomError(
            vault,
            'Vault__OptionTypeMismatchWithVault',
          );
        });

        it('should revert on trying to sell to the vault', async () => {
          const { poolKey, vault, trader, spot, timestamp } = await loadFixture(
            setup,
          );

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          const tradeSize = parseEther('3');

          await expect(
            vault
              .connect(trader)
              .trade(poolKey, tradeSize, false, parseEther('1000')),
          ).to.be.revertedWithCustomError(vault, 'Vault__TradeMustBeBuy');
        });

        it('should revert on trying to buy an option that is expired', async () => {
          const { poolKey, vault, trader, maturity, spot } = await loadFixture(
            setup,
          );

          await vault.setTimestamp(maturity + 3 * ONE_HOUR);
          await vault.setSpotPrice(spot);

          const tradeSize = parseEther('3');

          await expect(
            vault
              .connect(trader)
              .trade(poolKey, tradeSize, true, parseEther('1000')),
          ).to.be.revertedWithCustomError(vault, 'Vault__OptionExpired');
        });

        it('should revert on trying to buy an option not within the DTE bounds', async () => {
          const {
            base,
            quote,
            trader,
            callVault,
            putVault,
            volOracle,
            oracleAdapter,
            deployer,
            lp,
            p,
          } = await loadFixture(vaultSetup);

          vault = isCall ? callVault : putVault;
          const spot = parseEther('1000');
          const xstrike = 1100;
          const strike = parseEther('1100');
          const timestamp = await getValidMaturity(1, 'weeks');
          const maturity = await getValidMaturity(2, 'months');

          const { poolKey } = await createPool(
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
            .withArgs(base.address, spot, strike, '191780821917808219')
            .returns(parseEther('1.54'));
          await volOracle.mock['getVolatility(address,uint256,uint256,uint256)']
            .withArgs(base.address, spot, strike, '134246575342465753')
            .returns(parseEther('1.54'));

          const depositSize = isCall ? 5 : 5 * xstrike;
          await addDeposit(vault, lp, depositSize, base, quote);

          const tradeSize = parseEther('3');

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          await expect(
            vault
              .connect(trader)
              .trade(poolKey, tradeSize, true, parseEther('1000')),
          ).to.be.revertedWithCustomError(vault, 'Vault__OutOfDTEBounds');
        });

        it('should revert on trying to buy an option not within the delta bounds', async () => {
          const {
            base,
            quote,
            trader,
            callVault,
            putVault,
            volOracle,
            oracleAdapter,
            deployer,
            lp,
            p,
          } = await loadFixture(vaultSetup);

          vault = isCall ? callVault : putVault;
          const spot = parseEther('1000');
          const xstrike = 1500;
          const strike = parseEther('1500'); // ATM
          const timestamp = await getValidMaturity(2, 'weeks');
          const maturity = await getValidMaturity(3, 'weeks');

          const { poolKey } = await createPool(
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
          await addDeposit(vault, lp, depositSize, base, quote);

          const tradeSize = parseEther('3');

          await vault.setTimestamp(timestamp);
          await vault.setSpotPrice(spot);

          await expect(
            vault
              .connect(trader)
              .trade(poolKey, tradeSize, true, parseEther('1000')),
          ).to.be.revertedWithCustomError(vault, 'Vault__OutOfDeltaBounds');
        });
      });
    }
  });
});
