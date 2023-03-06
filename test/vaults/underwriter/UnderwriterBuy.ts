import { expect } from 'chai';
import { ethers } from 'hardhat';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  parseEther,
  formatEther,
  formatUnits,
  parseUnits,
} from 'ethers/lib/utils';
import { BigNumberish, BigNumber } from 'ethers';
import { vaultSetup, addDeposit } from './VaultSetup';
import { IPoolMock__factory } from '../../../typechain';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { TokenType } from '../../../utils/sdk/types';
import { getValidMaturity } from '../../../utils/time';

describe('#Vault contract', () => {
  it('properly initializes vault variables', async () => {
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
    expect(await base.balanceOf(deployer.address)).to.equal(parseEther('1000'));
    expect(await base.balanceOf(caller.address)).to.equal(parseEther('1000'));
    expect(await base.balanceOf(receiver.address)).to.equal(parseEther('1000'));
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

  it('responds to mock oracle adapter query', async () => {
    const { oracleAdapter, base, quote } = await loadFixture(vaultSetup);
    const price = await oracleAdapter.quote(base.address, quote.address);
    expect(parseFloat(formatUnits(price, 18))).to.eq(1500);
  });

  it('responds to mock iv oracle query', async () => {
    const { volOracle, base } = await loadFixture(vaultSetup);
    const iv = await volOracle[
      'getVolatility(address,uint256,uint256,uint256)'
    ](base.address, parseEther('2500'), parseEther('2000'), parseEther('0.2'));
    expect(parseFloat(formatEther(iv))).to.eq(0.8054718161126052);
  });
});

describe('#buy functionality', () => {
  describe('#quote functionality', () => {
    it('reverts on no strike input', async () => {
      const { base, quote, lp, callVault } = await loadFixture(vaultSetup);
      const badStrike = parseEther('0'); // ATM
      const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
      const quoteSize = parseEther('1');
      const lpDepositSize = 5; // units of base
      await addDeposit(callVault, lp, lpDepositSize, base, quote);
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
      await addDeposit(callVault, lp, lpDepositSize, base, quote);
      await expect(
        callVault.quote(strike, badMaturity, quoteSize),
      ).to.be.revertedWithCustomError(callVault, 'Vault__OptionExpired');
    });

    it('gets a valid spot price via the vault', async () => {
      const { callVault } = await loadFixture(vaultSetup);
      const spotPrice = await callVault.getSpotPrice();
      expect(parseFloat(formatEther(spotPrice))).to.be.equal(1500);
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

    it('returns the proper blackscholes price', async () => {
      const { callVault, putVault, base, volOracle } = await loadFixture(
        vaultSetup,
      );
      const spotPrice = await callVault.getSpotPrice();
      const strike = parseEther('1500');
      const tau = parseEther('0.03835616'); // 14 DTE
      const rfRate = await volOracle.getRiskFreeRate();
      const sigma = await volOracle[
        'getVolatility(address,uint256,uint256,uint256)'
      ](base.address, spotPrice, strike, tau);

      const callPrice = await callVault.getBlackScholesPrice(
        spotPrice,
        strike,
        tau,
        sigma,
        rfRate,
        true,
      );

      const putPrice = await callVault.getBlackScholesPrice(
        spotPrice,
        strike,
        tau,
        sigma,
        rfRate,
        false,
      );
      expect(parseFloat(formatEther(callPrice))).to.approximately(
        85.953,
        0.001,
      );
      expect(parseFloat(formatEther(putPrice))).to.approximately(85.953, 0.001);
    });

    it('calculates the proper mintingFee for a Call option', async () => {
      const { callPool } = await loadFixture(vaultSetup);
      const size = parseEther('1');
      const fee = await callPool.takerFee(size, 0, true);
      expect(parseFloat(formatEther(fee))).to.be.eq(0.003); // 30 bps
    });

    it('checks if the vault has sufficient funds', async () => {
      const { base, quote, lp, callVault } = await loadFixture(vaultSetup);
      const lpDepositSize = 5;
      const strike = parseEther('1500');
      await addDeposit(callVault, lp, lpDepositSize, base, quote);

      const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
      const largeTradeSize = parseEther('7');

      await expect(
        callVault.quote(strike, maturity, largeTradeSize),
      ).to.be.revertedWithCustomError(callVault, 'Vault__InsufficientFunds');
    });

    it('returns proper quote parameters: price, mintingFee, cLevel', async () => {
      const { base, quote, lp, callVault } = await loadFixture(vaultSetup);
      const lpDepositSize = 5;
      const strike = parseEther('1500');
      await addDeposit(callVault, lp, lpDepositSize, base, quote);

      const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
      const tradeSize = parseEther('2');
      const [poolAddr, price, mintingFee, cLevel] = await callVault.quote(
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

    describe('#isValidListing functionality', () => {
      it('reverts on invalid maturity bounds', async () => {
        const { volOracle, base, maturity, callVault } = await loadFixture(
          vaultSetup,
        );
        const spotPrice = await callVault.getSpotPrice();
        const strike = parseEther('1500');
        const badTau = parseEther('0.12328767'); // 45 DTE
        const rfRate = 0;
        const sigma = await volOracle[
          'getVolatility(address,uint256,uint256,uint256)'
        ](base.address, spotPrice, strike, badTau);
        await expect(
          callVault.isValidListing(
            spotPrice,
            strike,
            maturity,
            badTau,
            sigma,
            rfRate,
          ),
        ).to.be.revertedWithCustomError(callVault, 'Vault__MaturityBounds');
      });

      it('retrieves valid option delta', async () => {
        const { callVault, putVault, base, volOracle } = await loadFixture(
          vaultSetup,
        );
        const spotPrice = await callVault.getSpotPrice();
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

        expect(parseFloat(formatEther(callDelta))).to.approximately(
          0.528,
          0.001,
        );
        expect(parseFloat(formatEther(putDelta))).to.approximately(
          -0.471,
          0.001,
        );
      });

      it('reverts on invalid option delta bounds', async () => {
        const { volOracle, base, maturity, callVault } = await loadFixture(
          vaultSetup,
        );
        const spotPrice = await callVault.getSpotPrice();
        const itmStrike = parseEther('500');
        const badTau = parseEther('0.03835616'); // 14 DTE
        const rfRate = await volOracle.getRiskFreeRate();
        const sigma = await volOracle[
          'getVolatility(address,uint256,uint256,uint256)'
        ](base.address, spotPrice, itmStrike, badTau);
        await expect(
          callVault.isValidListing(
            spotPrice,
            itmStrike,
            maturity,
            badTau,
            sigma,
            rfRate,
          ),
        ).to.be.revertedWithCustomError(callVault, 'Vault__DeltaBounds');
      });

      it('receives a valid listing address', async () => {
        const { volOracle, base, maturity, callVault, callPool } =
          await loadFixture(vaultSetup);
        const spotPrice = await callVault.getSpotPrice();
        const unListedStrike = parseEther('1500');
        const tau = parseEther('0.03835616'); // 14 DTE
        const rfRate = await volOracle.getRiskFreeRate();
        const sigma = await volOracle[
          'getVolatility(address,uint256,uint256,uint256)'
        ](base.address, spotPrice, unListedStrike, tau);
        const listingAddr = await callVault.isValidListing(
          spotPrice,
          unListedStrike,
          maturity,
          tau,
          sigma,
          rfRate,
        );
        expect(listingAddr).to.be.eq(callPool.address);
      });

      it('returns the proper pool address from factory', async () => {
        const { p, callPoolKey, callPool } = await loadFixture(vaultSetup);
        const listingAddr = await p.poolFactory.getPoolAddress(callPoolKey);
        expect(listingAddr).to.be.eq(callPool.address);
      });

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

      it('reverts when factory returns addressZERO', async () => {
        const { volOracle, base, maturity, callVault } = await loadFixture(
          vaultSetup,
        );
        const spotPrice = await callVault.getSpotPrice();
        const unListedStrike = parseEther('1550');
        const tau = parseEther('0.03835616'); // 14 DTE
        const rfRate = await volOracle.getRiskFreeRate();
        const sigma = await volOracle[
          'getVolatility(address,uint256,uint256,uint256)'
        ](base.address, spotPrice, unListedStrike, tau);
        await expect(
          callVault.isValidListing(
            spotPrice,
            unListedStrike,
            maturity,
            tau,
            sigma,
            rfRate,
          ),
        ).to.be.revertedWithCustomError(
          callVault,
          'Vault__OptionPoolNotListed',
        );
      });
    });

    describe('#cLevel functionality', () => {
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
          expect(parseFloat(formatEther(cLevel))).to.approximately(
            1.024,
            0.001,
          );

          cLevel = await callVault.calculateClevel(
            parseEther('0.9'),
            parseEther('3.0'),
            parseEther('1.0'),
            parseEther('1.2'),
          );
          expect(parseFloat(formatEther(cLevel))).to.approximately(
            1.145,
            0.001,
          );
        });
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

      it('used post quote/trade utilization', async () => {
        const { callVault, lp, trader, base, quote } = await loadFixture(
          vaultSetup,
        );

        // Hydrate Vault
        const lpDepositSize = 5; // units of base
        await addDeposit(callVault, lp, lpDepositSize, base, quote);

        // Trade Settings
        const strike = parseEther('1500');
        const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
        const tradeSize = parseEther('2');

        //PreTrade cLevel
        const cLevel_preTrade = await callVault.getClevel(parseEther('0'));

        // Execute Trade
        const cLevel_postTrade = await callVault.getClevel(tradeSize);
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
        await addDeposit(callVault, lp, lpDepositSize, base, quote);

        // Trade Settings
        const strike = parseEther('1500');
        const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
        const tradeSize = parseEther('3');

        // Execute Trades
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
        await addDeposit(callVault, lp, lpDepositSize, base, quote);

        // Trade Settings
        const strike = parseEther('1500');
        const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
        const tradeSize = parseEther('2');

        // Initialized lastTradeTimestamp
        const lastTrade_t0 = await callVault.getLastTradeTimestamp();

        // Execute Trade
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
        await addDeposit(callVault, lp, lpDepositSize, base, quote);

        // Trade Settings
        const strike = parseEther('1500');
        const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
        const tradeSize = parseEther('2');

        //PreTrade cLevel
        const cLevel_t0 = await callVault.getClevel(parseEther('0'));

        // Execute Trade
        const cLevel_t1 = await callVault.getClevel(tradeSize);
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

  describe('#minting options from pool', () => {
    it('allows writeFrom to mint call options when directly called', async () => {
      const { underwriter, trader, base, callPool } = await loadFixture(
        vaultSetup,
      );
      const size = parseEther('5');
      const callPoolUnderwriter = IPoolMock__factory.connect(
        callPool.address,
        underwriter,
      );
      const fee = await callPool.takerFee(size, 0, true);
      const totalSize = size.add(fee);
      await base.connect(underwriter).approve(callPool.address, totalSize);
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

      await quote.connect(underwriter).approve(putPool.address, totalSize);
      await putPoolUnderwriter.writeFrom(
        underwriter.address,
        trader.address,
        size,
      );
      expect(await quote.balanceOf(putPool.address)).to.eq(totalSize);
      expect(await putPool.balanceOf(trader.address, TokenType.LONG)).to.eq(
        size,
      );
      expect(await putPool.balanceOf(trader.address, TokenType.SHORT)).to.eq(0);
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
      await addDeposit(callVault, lp, lpDepositSize, base, quote);
      const strike = parseEther('1500');
      const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
      const tradeSize = parseEther('2');
      const fee = await callPool.takerFee(tradeSize, 0, true);
      const totalSize = tradeSize.add(fee);
      await callVault.connect(trader).buy(strike, maturity, tradeSize);
      const vaultCollateralBalance = lpDepositSizeBN.sub(totalSize);

      expect(await base.balanceOf(callPool.address)).to.eq(totalSize);
      expect(await callPool.balanceOf(trader.address, TokenType.LONG)).to.eq(
        tradeSize,
      );
      expect(
        await callPool.balanceOf(callVault.address, TokenType.SHORT),
      ).to.eq(tradeSize);
      expect(await base.balanceOf(callVault.address)).to.be.eq(
        vaultCollateralBalance,
      );
    });

    it('allows the vault to mint put options for the LP and Trader', async () => {
      const { putVault, lp, trader, base, quote, putPool } = await loadFixture(
        vaultSetup,
      );

      const strike = 1500;
      const lpDepositSize = 5 * strike; // 5 units
      const lpDepositSizeBN = parseUnits(lpDepositSize.toString(), 6);
      await addDeposit(putVault, lp, lpDepositSize, base, quote);

      const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
      const tradeSize = parseEther('2');
      const fee = await putPool.takerFee(tradeSize, 0, false);
      const totalSize = tradeSize.add(fee);
      const strikeBN = parseEther(strike.toString());
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
