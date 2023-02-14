import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  ERC20Mock,
  ERC20Mock__factory,
  IPoolMock,
  IPoolMock__factory,
} from '../../typechain';
import { BigNumber } from 'ethers';
import { parseEther, parseUnits } from 'ethers/lib/utils';
import { PoolUtil } from '../../utils/PoolUtil';
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract';
import {
  getValidMaturity,
  increaseTo,
  now,
  ONE_HOUR,
  revertToSnapshotAfterEach,
} from '../../utils/time';
import { signQuote, TradeQuote } from '../../utils/sdk/quote';
import { average, bnToNumber } from '../../utils/sdk/math';
import { OrderType, PositionKey, TokenType } from '../../utils/sdk/types';
import { ONE_ETHER, THREE_ETHER } from '../../utils/constants';

const depositFnSig =
  'deposit((address,address,uint256,uint256,uint8,bool,uint256),uint256,uint256,uint256,uint256)';

describe('Pool', () => {
  let deployer: SignerWithAddress;
  let lp: SignerWithAddress;
  let trader: SignerWithAddress;

  let callPool: IPoolMock;
  let putPool: IPoolMock;
  let p: PoolUtil;

  let base: ERC20Mock;
  let quote: ERC20Mock;

  let baseOracle: MockContract;
  let quoteOracle: MockContract;

  let strike = parseEther('1000'); // ATM
  let maturity: number;

  let isCall: boolean;
  let collateral: BigNumber;

  let pKey: PositionKey;

  let getTradeQuote: () => Promise<TradeQuote>;

  before(async () => {
    [deployer, lp, trader] = await ethers.getSigners();

    base = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
    quote = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

    baseOracle = await deployMockContract(deployer as any, [
      'function latestAnswer() external view returns (int256)',
      'function decimals () external view returns (uint8)',
    ]);

    await baseOracle.mock.latestAnswer.returns(parseUnits('1000', 8));
    await baseOracle.mock.decimals.returns(8);

    quoteOracle = await deployMockContract(deployer as any, [
      'function latestAnswer() external view returns (int256)',
      'function decimals () external view returns (uint8)',
    ]);

    await quoteOracle.mock.latestAnswer.returns(parseUnits('1', 8));
    await quoteOracle.mock.decimals.returns(8);

    p = await PoolUtil.deploy(
      deployer,
      base.address,
      baseOracle.address,
      deployer.address,
      parseEther('0.1'), // 10%
      true,
      true,
    );

    maturity = await getValidMaturity(10, 'months');

    for (isCall of [true, false]) {
      const tx = await p.poolFactory.deployPool(
        {
          base: base.address,
          quote: quote.address,
          baseOracle: baseOracle.address,
          quoteOracle: quoteOracle.address,
          strike: strike,
          maturity: maturity,
          isCallPool: isCall,
        },
        {
          value: parseEther('1'),
        },
      );

      const r = await tx.wait(1);
      const poolAddress = (r as any).events[0].args.poolAddress;

      if (isCall) {
        callPool = IPoolMock__factory.connect(poolAddress, deployer);
        collateral = parseEther('10');
      } else {
        putPool = IPoolMock__factory.connect(poolAddress, deployer);
        collateral = parseEther('1000');
      }
    }

    getTradeQuote = async () => {
      return {
        provider: lp.address,
        taker: trader.address,
        price: parseEther('0.1').toString(),
        size: parseEther('10').toString(),
        isBuy: false,
        deadline: (await now()) + ONE_HOUR,
        nonce: 0,
      };
    };
  });

  beforeEach(async () => {
    pKey = {
      owner: lp.address,
      operator: lp.address,
      lower: parseEther('0.1'),
      upper: parseEther('0.3'),
      orderType: OrderType.LC,
      isCall: isCall,
      strike: strike,
    };
  });

  revertToSnapshotAfterEach(async () => {});

  describe('__internal', function () {
    describe('#_getPricing', () => {
      it('should return pool state', async () => {
        let isBuy = true;
        let args = await callPool._getPricing(isBuy);

        expect(args.liquidityRate).to.eq(0);
        expect(args.marketPrice).to.eq(parseEther('0.001'));
        expect(args.lower).to.eq(parseEther('0.001'));
        expect(args.upper).to.eq(parseEther('1'));
        expect(args.isBuy).to.eq(isBuy);

        args = await callPool._getPricing(!isBuy);

        expect(args.liquidityRate).to.eq(0);
        expect(args.marketPrice).to.eq(parseEther('0.001'));
        expect(args.lower).to.eq(parseEther('0.001'));
        expect(args.upper).to.eq(parseEther('1'));
        expect(args.isBuy).to.eq(!isBuy);

        let lower = parseEther('0.25');
        let upper = parseEther('0.75');

        let position = {
          lower: lower,
          upper: upper,
          operator: lp.address,
          owner: lp.address,
          orderType: OrderType.LC,
          isCall: isCall,
          strike: strike,
        };

        await base.connect(lp).approve(callPool.address, collateral);

        const nearestBelow = await callPool.getNearestTicksBelow(lower, upper);

        await base.mint(lp.address, parseEther('2000'));

        await callPool
          .connect(lp)
          [
            'deposit((address,address,uint256,uint256,uint8,bool,uint256),uint256,uint256,uint256,uint256)'
          ](
            position,
            nearestBelow.nearestBelowLower,
            nearestBelow.nearestBelowUpper,
            parseEther('2000'),
            0,
          );

        args = await callPool._getPricing(isBuy);

        expect(args.liquidityRate).to.eq(parseEther('4'));
        expect(args.marketPrice).to.eq(upper);
        expect(args.lower).to.eq(lower);
        expect(args.upper).to.eq(upper);
        expect(args.isBuy).to.eq(isBuy);

        args = await callPool._getPricing(!isBuy);

        expect(args.liquidityRate).to.eq(parseEther('4'));
        expect(args.marketPrice).to.eq(upper);
        expect(args.lower).to.eq(lower);
        expect(args.upper).to.eq(upper);
        expect(args.isBuy).to.eq(!isBuy);
      });
    });
  });

  describe('#getTradeQuote', () => {
    it('should successfully return a buy trade quote', async () => {
      const nearestBelow = await callPool.getNearestTicksBelow(
        pKey.lower,
        pKey.upper,
      );
      const depositSize = parseEther('1000');

      await base.mint(lp.address, depositSize);
      await base.connect(lp).approve(callPool.address, depositSize);

      await callPool
        .connect(lp)
        [depositFnSig](
          { ...pKey, orderType: OrderType.CS },
          nearestBelow.nearestBelowLower,
          nearestBelow.nearestBelowUpper,
          depositSize,
          0,
        );

      const tradeSize = parseEther('500');
      const price = pKey.lower;
      const nextPrice = parseEther('0.2');
      const avgPrice = average(price, nextPrice);
      const takerFee = await callPool.takerFee(
        tradeSize,
        tradeSize.mul(avgPrice).div(ONE_ETHER),
      );

      expect(await callPool.getTradeQuote(tradeSize, true)).to.eq(
        tradeSize.mul(avgPrice).div(ONE_ETHER).add(takerFee),
      );
    });

    it('should successfully return a sell trade quote', async () => {
      const nearestBelow = await callPool.getNearestTicksBelow(
        pKey.lower,
        pKey.upper,
      );
      const depositSize = parseEther('1000');

      await base.mint(lp.address, depositSize);
      await base.connect(lp).approve(callPool.address, depositSize);

      await callPool
        .connect(lp)
        [depositFnSig](
          { ...pKey, orderType: OrderType.LC },
          nearestBelow.nearestBelowLower,
          nearestBelow.nearestBelowUpper,
          depositSize,
          0,
        );

      const tradeSize = parseEther('500');
      const price = pKey.upper;
      const nextPrice = parseEther('0.2');
      const avgPrice = average(price, nextPrice);
      const takerFee = await callPool.takerFee(
        tradeSize,
        tradeSize.mul(avgPrice).div(ONE_ETHER),
      );

      expect(await callPool.getTradeQuote(tradeSize, false)).to.eq(
        tradeSize.mul(avgPrice).div(ONE_ETHER).sub(takerFee),
      );
    });

    it('should revert if not enough liquidity to buy', async () => {
      const nearestBelow = await callPool.getNearestTicksBelow(
        pKey.lower,
        pKey.upper,
      );
      const size = parseEther('1000');

      await base.mint(lp.address, size);
      await base.connect(lp).approve(callPool.address, size);

      await callPool
        .connect(lp)
        [depositFnSig](
          { ...pKey, orderType: OrderType.CS },
          nearestBelow.nearestBelowLower,
          nearestBelow.nearestBelowUpper,
          size,
          0,
        );

      await expect(
        callPool.getTradeQuote(size.add(1), true),
      ).to.be.revertedWithCustomError(callPool, 'Pool__InsufficientLiquidity');
    });

    it('should revert if not enough liquidity to sell', async () => {
      const nearestBelow = await callPool.getNearestTicksBelow(
        pKey.lower,
        pKey.upper,
      );
      const size = parseEther('1000');

      await base.mint(lp.address, size);
      await base.connect(lp).approve(callPool.address, size);

      await callPool
        .connect(lp)
        [depositFnSig](
          { ...pKey, orderType: OrderType.LC },
          nearestBelow.nearestBelowLower,
          nearestBelow.nearestBelowUpper,
          size,
          0,
        );

      await expect(
        callPool.getTradeQuote(size.add(1), false),
      ).to.be.revertedWithCustomError(callPool, 'Pool__InsufficientLiquidity');
    });
  });

  describe('#deposit', () => {
    const fnSig = depositFnSig;

    describe(`#${fnSig}`, () => {
      describe('OrderType LC', () => {
        it('should mint 1000 LP tokens and deposit 200 collateral (lower: 0.1 | upper 0.3 | size: 1000)', async () => {
          const tokenId = await callPool.formatTokenId(
            pKey.operator,
            pKey.lower,
            pKey.upper,
            pKey.orderType,
          );

          expect(await callPool.balanceOf(lp.address, tokenId)).to.eq(0);

          const nearestBelow = await callPool.getNearestTicksBelow(
            pKey.lower,
            pKey.upper,
          );
          const size = parseEther('1000');

          await base.mint(lp.address, size);
          await base.connect(lp).approve(callPool.address, size);

          await callPool
            .connect(lp)
            [fnSig](
              pKey,
              nearestBelow.nearestBelowLower,
              nearestBelow.nearestBelowUpper,
              size,
              0,
            );

          const averagePrice = average(pKey.lower, pKey.upper);
          const collateralValue = size.mul(averagePrice).div(ONE_ETHER);

          expect(await callPool.balanceOf(lp.address, tokenId)).to.eq(size);
          expect(await callPool.totalSupply(tokenId)).to.eq(size);
          expect(await base.balanceOf(callPool.address)).to.eq(collateralValue);
          expect(await base.balanceOf(lp.address)).to.eq(
            size.sub(collateralValue),
          );
          expect(await callPool.marketPrice()).to.eq(pKey.upper);
        });
      });

      it('should revert if msg.sender != p.operator', async () => {
        await expect(
          callPool.connect(deployer)[fnSig](pKey, 0, 0, THREE_ETHER, 0),
        ).to.be.revertedWithCustomError(callPool, 'Pool__NotAuthorized');
      });

      it('should revert if above max slippage'); // ToDo

      it('should revert if zero size', async () => {
        await expect(
          callPool.connect(lp)[fnSig](pKey, 0, 0, 0, 0),
        ).to.be.revertedWithCustomError(callPool, 'Pool__ZeroSize');
      });

      it('should revert if option is expired', async () => {
        await increaseTo(maturity);
        await expect(
          callPool.connect(lp)[fnSig](pKey, 0, 0, THREE_ETHER, 0),
        ).to.be.revertedWithCustomError(callPool, 'Pool__OptionExpired');
      });

      it('should revert if range is not valid', async () => {
        await expect(
          callPool
            .connect(lp)
            [fnSig]({ ...pKey, lower: 0 }, 0, 0, THREE_ETHER, 0),
        ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidRange');

        await expect(
          callPool
            .connect(lp)
            [fnSig]({ ...pKey, upper: 0 }, 0, 0, THREE_ETHER, 0),
        ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidRange');

        await expect(
          callPool
            .connect(lp)
            [fnSig](
              { ...pKey, lower: parseEther('0.5'), upper: parseEther('0.25') },
              0,
              0,
              THREE_ETHER,
              0,
            ),
        ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidRange');

        await expect(
          callPool
            .connect(lp)
            [fnSig](
              { ...pKey, lower: parseEther('0.0001') },
              0,
              0,
              THREE_ETHER,
              0,
            ),
        ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidRange');

        await expect(
          callPool
            .connect(lp)
            [fnSig](
              { ...pKey, upper: parseEther('1.01') },
              0,
              0,
              THREE_ETHER,
              0,
            ),
        ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidRange');
      });

      it('should revert if tick width is invalid', async () => {
        await expect(
          callPool
            .connect(lp)
            [fnSig](
              { ...pKey, lower: parseEther('0.2501') },
              0,
              0,
              THREE_ETHER,
              0,
            ),
        ).to.be.revertedWithCustomError(callPool, 'Pool__TickWidthInvalid');

        await expect(
          callPool
            .connect(lp)
            [fnSig](
              { ...pKey, upper: parseEther('0.7501') },
              0,
              0,
              THREE_ETHER,
              0,
            ),
        ).to.be.revertedWithCustomError(callPool, 'Pool__TickWidthInvalid');
      });
    });
  });

  describe('#withdraw', () => {
    describe('OrderType LC', () => {
      it('should burn 750 LP tokens and withdraw 150 collateral (lower: 0.1 | upper 0.3 | size: 750)', async () => {
        const tokenId = await callPool.formatTokenId(
          pKey.operator,
          pKey.lower,
          pKey.upper,
          pKey.orderType,
        );

        const nearestBelow = await callPool.getNearestTicksBelow(
          pKey.lower,
          pKey.upper,
        );
        const size = parseEther('1000');

        const depositCollateralValue = parseEther('200');
        await base.mint(lp.address, depositCollateralValue);
        await base
          .connect(lp)
          .approve(callPool.address, depositCollateralValue);

        await callPool
          .connect(lp)
          [
            'deposit((address,address,uint256,uint256,uint8,bool,uint256),uint256,uint256,uint256,uint256)'
          ](
            pKey,
            nearestBelow.nearestBelowLower,
            nearestBelow.nearestBelowUpper,
            size,
            0,
          );

        expect(await base.balanceOf(lp.address)).to.eq(0);
        expect(await base.balanceOf(callPool.address)).to.eq(parseEther('200'));

        const withdrawSize = parseEther('750');

        const averagePrice = average(pKey.lower, pKey.upper);
        const withdrawCollateralValue = withdrawSize
          .mul(averagePrice)
          .div(ONE_ETHER);

        await callPool.connect(lp).withdraw(pKey, withdrawSize, 0);
        expect(await callPool.balanceOf(lp.address, tokenId)).to.eq(
          parseEther('250'),
        );
        expect(await callPool.totalSupply(tokenId)).to.eq(parseEther('250'));
        expect(await base.balanceOf(callPool.address)).to.eq(
          depositCollateralValue.sub(withdrawCollateralValue),
        );
        expect(await base.balanceOf(lp.address)).to.eq(withdrawCollateralValue);
      });
    });

    it('should revert if msg.sender != p.operator', async () => {
      await expect(
        callPool.connect(deployer).withdraw(pKey, THREE_ETHER, 0),
      ).to.be.revertedWithCustomError(callPool, 'Pool__NotAuthorized');
    });

    it('should revert if above max slippage'); // ToDo

    it('should revert if zero size', async () => {
      await expect(
        callPool.connect(lp).withdraw(pKey, 0, 0),
      ).to.be.revertedWithCustomError(callPool, 'Pool__ZeroSize');
    });

    it('should revert if option is expired', async () => {
      await increaseTo(maturity);
      await expect(
        callPool.connect(lp).withdraw(pKey, THREE_ETHER, 0),
      ).to.be.revertedWithCustomError(callPool, 'Pool__OptionExpired');
    });

    it('should revert if position does not exists', async () => {
      await expect(
        callPool.connect(lp).withdraw(pKey, THREE_ETHER, 0),
      ).to.be.revertedWithCustomError(callPool, 'Pool__PositionDoesNotExist');
    });

    it('should revert if range is not valid', async () => {
      await expect(
        callPool.connect(lp).withdraw({ ...pKey, lower: 0 }, THREE_ETHER, 0),
      ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidRange');

      await expect(
        callPool.connect(lp).withdraw({ ...pKey, upper: 0 }, THREE_ETHER, 0),
      ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidRange');

      await expect(
        callPool
          .connect(lp)
          .withdraw(
            { ...pKey, lower: parseEther('0.5'), upper: parseEther('0.25') },
            THREE_ETHER,
            0,
          ),
      ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidRange');

      await expect(
        callPool
          .connect(lp)
          .withdraw({ ...pKey, lower: parseEther('0.0001') }, THREE_ETHER, 0),
      ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidRange');

      await expect(
        callPool
          .connect(lp)
          .withdraw({ ...pKey, upper: parseEther('1.01') }, THREE_ETHER, 0),
      ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidRange');
    });

    it('should revert if tick width is invalid', async () => {
      await expect(
        callPool
          .connect(lp)
          .withdraw({ ...pKey, lower: parseEther('0.2501') }, THREE_ETHER, 0),
      ).to.be.revertedWithCustomError(callPool, 'Pool__TickWidthInvalid');

      await expect(
        callPool
          .connect(lp)
          .withdraw({ ...pKey, upper: parseEther('0.7501') }, THREE_ETHER, 0),
      ).to.be.revertedWithCustomError(callPool, 'Pool__TickWidthInvalid');
    });
  });

  describe('#trade', () => {
    it('should successfully buy 500 options', async () => {
      const nearestBelow = await callPool.getNearestTicksBelow(
        pKey.lower,
        pKey.upper,
      );
      const depositSize = parseEther('1000');

      await base.mint(lp.address, depositSize);
      await base.connect(lp).approve(callPool.address, depositSize);

      await callPool
        .connect(lp)
        [depositFnSig](
          { ...pKey, orderType: OrderType.CS },
          nearestBelow.nearestBelowLower,
          nearestBelow.nearestBelowUpper,
          depositSize,
          0,
        );

      const tradeSize = parseEther('500');
      const totalPremium = await callPool.getTradeQuote(tradeSize, true);

      await base.mint(trader.address, totalPremium);
      await base.connect(trader).approve(callPool.address, totalPremium);

      await callPool.connect(trader).trade(tradeSize, true);

      expect(await callPool.balanceOf(trader.address, TokenType.LONG)).to.eq(
        tradeSize,
      );
      expect(await callPool.balanceOf(callPool.address, TokenType.SHORT)).to.eq(
        tradeSize,
      );
      expect(await base.balanceOf(trader.address)).to.eq(0);
    });

    it('should successfully sell 500 options', async () => {
      const nearestBelow = await callPool.getNearestTicksBelow(
        pKey.lower,
        pKey.upper,
      );
      const depositSize = parseEther('1000');

      await base.mint(lp.address, depositSize);
      await base.connect(lp).approve(callPool.address, depositSize);

      await callPool
        .connect(lp)
        [depositFnSig](
          { ...pKey, orderType: OrderType.LC },
          nearestBelow.nearestBelowLower,
          nearestBelow.nearestBelowUpper,
          depositSize,
          0,
        );

      const tradeSize = parseEther('500');
      const totalPremium = await callPool.getTradeQuote(tradeSize, false);

      await base.mint(trader.address, tradeSize);
      await base.connect(trader).approve(callPool.address, tradeSize);

      await callPool.connect(trader).trade(tradeSize, false);

      expect(await callPool.balanceOf(trader.address, TokenType.SHORT)).to.eq(
        tradeSize,
      );
      expect(await callPool.balanceOf(callPool.address, TokenType.LONG)).to.eq(
        tradeSize,
      );
      expect(await base.balanceOf(trader.address)).to.eq(totalPremium);
    });

    it('should revert if trying to buy options and ask liquidity is insufficient', async () => {
      const nearestBelow = await callPool.getNearestTicksBelow(
        pKey.lower,
        pKey.upper,
      );
      const depositSize = parseEther('1000');

      await base.mint(lp.address, depositSize);
      await base.connect(lp).approve(callPool.address, depositSize);

      await callPool
        .connect(lp)
        [depositFnSig](
          { ...pKey, orderType: OrderType.CS },
          nearestBelow.nearestBelowLower,
          nearestBelow.nearestBelowUpper,
          depositSize,
          0,
        );

      await expect(
        callPool.connect(trader).trade(depositSize.add(1), true),
      ).to.be.revertedWithCustomError(
        callPool,
        'Pool__InsufficientAskLiquidity',
      );
    });

    it('should revert if trying to sell options and bid liquidity is insufficient', async () => {
      const nearestBelow = await callPool.getNearestTicksBelow(
        pKey.lower,
        pKey.upper,
      );
      const depositSize = parseEther('1000');

      await base.mint(lp.address, depositSize);
      await base.connect(lp).approve(callPool.address, depositSize);

      await callPool
        .connect(lp)
        [depositFnSig](
          { ...pKey, orderType: OrderType.LC },
          nearestBelow.nearestBelowLower,
          nearestBelow.nearestBelowUpper,
          depositSize,
          0,
        );

      await expect(
        callPool.connect(trader).trade(depositSize.add(1), false),
      ).to.be.revertedWithCustomError(
        callPool,
        'Pool__InsufficientBidLiquidity',
      );
    });

    it('should revert if trade size is 0', async () => {
      await expect(
        callPool.connect(trader).trade(0, true),
      ).to.be.revertedWithCustomError(callPool, 'Pool__ZeroSize');
    });

    it('should revert if expired', async () => {
      await increaseTo(maturity);

      await expect(
        callPool.connect(trader).trade(1, true),
      ).to.be.revertedWithCustomError(callPool, 'Pool__OptionExpired');
    });
  });

  describe('#exercise', () => {
    it('should successfully exercise an ITM option', async () => {
      const nearestBelow = await callPool.getNearestTicksBelow(
        pKey.lower,
        pKey.upper,
      );
      const depositSize = ONE_ETHER;

      await base.mint(lp.address, depositSize);
      await base.connect(lp).approve(callPool.address, depositSize);

      await callPool
        .connect(lp)
        [depositFnSig](
          { ...pKey, orderType: OrderType.CS },
          nearestBelow.nearestBelowLower,
          nearestBelow.nearestBelowUpper,
          depositSize,
          0,
        );

      const tradeSize = ONE_ETHER;
      const totalPremium = await callPool.getTradeQuote(tradeSize, true);

      await base.mint(trader.address, totalPremium);
      await base.connect(trader).approve(callPool.address, totalPremium);

      await callPool.connect(trader).trade(tradeSize, true);

      await baseOracle.mock.latestAnswer.returns(parseUnits('1250', 8));

      await increaseTo(maturity);
      await callPool.exercise(trader.address);

      const exerciseValue = parseEther(((1250 - 1000) / 1250).toString());
      expect(await base.balanceOf(trader.address)).to.eq(exerciseValue);
      expect(await base.balanceOf(callPool.address)).to.eq(
        ONE_ETHER.add(totalPremium).sub(exerciseValue),
      );
      expect(await callPool.balanceOf(trader.address, TokenType.LONG)).to.eq(0);
      expect(await callPool.balanceOf(callPool.address, TokenType.SHORT)).to.eq(
        ONE_ETHER,
      );
    });

    it('should not pay any token when exercising an OTM option', async () => {
      const nearestBelow = await callPool.getNearestTicksBelow(
        pKey.lower,
        pKey.upper,
      );
      const depositSize = ONE_ETHER;

      await base.mint(lp.address, depositSize);
      await base.connect(lp).approve(callPool.address, depositSize);

      await callPool
        .connect(lp)
        [depositFnSig](
          { ...pKey, orderType: OrderType.CS },
          nearestBelow.nearestBelowLower,
          nearestBelow.nearestBelowUpper,
          depositSize,
          0,
        );

      const tradeSize = ONE_ETHER;
      const totalPremium = await callPool.getTradeQuote(tradeSize, true);

      await base.mint(trader.address, totalPremium);
      await base.connect(trader).approve(callPool.address, totalPremium);

      await callPool.connect(trader).trade(tradeSize, true);

      await baseOracle.mock.latestAnswer.returns(parseUnits('999', 8));

      await increaseTo(maturity);
      await callPool.exercise(trader.address);

      const exerciseValue = 0;
      expect(await base.balanceOf(trader.address)).to.eq(exerciseValue);
      expect(await base.balanceOf(callPool.address)).to.eq(
        ONE_ETHER.add(totalPremium).sub(exerciseValue),
      );
      expect(await callPool.balanceOf(trader.address, TokenType.LONG)).to.eq(0);
      expect(await callPool.balanceOf(callPool.address, TokenType.SHORT)).to.eq(
        ONE_ETHER,
      );
    });

    it('should revert if options is not expired', async () => {
      await expect(
        callPool.exercise(trader.address),
      ).to.be.revertedWithCustomError(callPool, 'Pool__OptionNotExpired');
    });
  });

  describe('#settle', () => {
    it('should successfully settle an ITM option', async () => {
      const nearestBelow = await callPool.getNearestTicksBelow(
        pKey.lower,
        pKey.upper,
      );
      const depositSize = ONE_ETHER;

      await base.mint(lp.address, depositSize);
      await base.connect(lp).approve(callPool.address, depositSize);

      await callPool
        .connect(lp)
        [depositFnSig](
          { ...pKey, orderType: OrderType.LC },
          nearestBelow.nearestBelowLower,
          nearestBelow.nearestBelowUpper,
          depositSize,
          0,
        );

      const tradeSize = depositSize;
      const price = pKey.lower;
      const nextPrice = pKey.upper;
      const avgPrice = average(price, nextPrice);
      const takerFee = await callPool.takerFee(
        tradeSize,
        tradeSize.mul(avgPrice).div(ONE_ETHER),
      );

      const totalPremium = await callPool.getTradeQuote(tradeSize, false);

      await base.mint(trader.address, ONE_ETHER);
      await base.connect(trader).approve(callPool.address, ONE_ETHER);

      await callPool.connect(trader).trade(tradeSize, false);

      await baseOracle.mock.latestAnswer.returns(parseUnits('1250', 8));

      await increaseTo(maturity);
      await callPool.settle(trader.address);

      const exerciseValue = parseEther(((1250 - 1000) / 1250).toString());
      expect(await base.balanceOf(trader.address)).to.eq(
        ONE_ETHER.add(totalPremium).sub(exerciseValue),
      );
      expect(await base.balanceOf(callPool.address)).to.eq(
        exerciseValue.add(takerFee),
      );
      expect(await callPool.balanceOf(trader.address, TokenType.SHORT)).to.eq(
        0,
      );
      expect(await callPool.balanceOf(callPool.address, TokenType.LONG)).to.eq(
        ONE_ETHER,
      );
    });

    it('should successfully settle an OTM option', async () => {
      const nearestBelow = await callPool.getNearestTicksBelow(
        pKey.lower,
        pKey.upper,
      );
      const depositSize = ONE_ETHER;

      await base.mint(lp.address, depositSize);
      await base.connect(lp).approve(callPool.address, depositSize);

      await callPool
        .connect(lp)
        [depositFnSig](
          { ...pKey, orderType: OrderType.LC },
          nearestBelow.nearestBelowLower,
          nearestBelow.nearestBelowUpper,
          depositSize,
          0,
        );

      const tradeSize = depositSize;
      const price = pKey.lower;
      const nextPrice = pKey.upper;
      const avgPrice = average(price, nextPrice);
      const takerFee = await callPool.takerFee(
        tradeSize,
        tradeSize.mul(avgPrice).div(ONE_ETHER),
      );
      const totalPremium = await callPool.getTradeQuote(tradeSize, false);

      await base.mint(trader.address, ONE_ETHER);
      await base.connect(trader).approve(callPool.address, ONE_ETHER);

      await callPool.connect(trader).trade(tradeSize, false);

      await baseOracle.mock.latestAnswer.returns(parseUnits('999', 8));

      await increaseTo(maturity);
      await callPool.settle(trader.address);

      const exerciseValue = BigNumber.from(0);
      expect(await base.balanceOf(trader.address)).to.eq(
        ONE_ETHER.add(totalPremium).sub(exerciseValue),
      );
      expect(await base.balanceOf(callPool.address)).to.eq(
        exerciseValue.add(takerFee),
      );
      expect(await callPool.balanceOf(trader.address, TokenType.SHORT)).to.eq(
        0,
      );
      expect(await callPool.balanceOf(callPool.address, TokenType.LONG)).to.eq(
        ONE_ETHER,
      );
    });

    it('should revert if not expired', async () => {
      await expect(
        callPool.settle(trader.address),
      ).to.be.revertedWithCustomError(callPool, 'Pool__OptionNotExpired');
    });
  });

  describe('#fillQuote', () => {
    it('should successfully fill a valid quote', async () => {
      const quote = await getTradeQuote();

      const initialBalance = parseEther('10');

      await base.mint(lp.address, initialBalance);
      await base.mint(trader.address, initialBalance);

      await base
        .connect(lp)
        .approve(callPool.address, ethers.constants.MaxUint256);
      await base
        .connect(trader)
        .approve(callPool.address, ethers.constants.MaxUint256);

      const sig = await signQuote(lp.provider!, callPool.address, quote);

      await callPool
        .connect(trader)
        .fillQuote(quote, quote.size, sig.v, sig.r, sig.s);

      const premium = BigNumber.from(quote.price).mul(
        bnToNumber(BigNumber.from(quote.size)),
      );

      const fee = (await callPool.takerFee(quote.size, premium)).div(2); // Divide by 2 to account for protocol fee

      expect(await base.balanceOf(lp.address)).to.eq(
        initialBalance.sub(quote.size).add(premium).sub(fee),
      );
      expect(await base.balanceOf(trader.address)).to.eq(
        initialBalance.sub(premium),
      );

      expect(await callPool.balanceOf(trader.address, TokenType.SHORT)).to.eq(
        0,
      );
      expect(await callPool.balanceOf(trader.address, TokenType.LONG)).to.eq(
        parseEther('10'),
      );

      expect(await callPool.balanceOf(lp.address, TokenType.SHORT)).to.eq(
        parseEther('10'),
      );
      expect(await callPool.balanceOf(lp.address, TokenType.LONG)).to.eq(0);
    });

    it('should revert if quote is expired', async () => {
      const quote = await getTradeQuote();
      quote.deadline = (await now()) - 1;

      const sig = await signQuote(lp.provider!, callPool.address, quote);

      await expect(
        callPool
          .connect(trader)
          .fillQuote(quote, quote.size, sig.v, sig.r, sig.s),
      ).to.be.revertedWithCustomError(callPool, 'Pool__QuoteExpired');
    });

    it('should revert if quote price is out of bounds', async () => {
      const quote = await getTradeQuote();
      quote.price = 1;

      let sig = await signQuote(lp.provider!, callPool.address, quote);

      await expect(
        callPool
          .connect(trader)
          .fillQuote(quote, quote.size, sig.v, sig.r, sig.s),
      ).to.be.revertedWithCustomError(callPool, 'Pool__OutOfBoundsPrice');

      quote.price = parseEther('1').add(1).toString();
      sig = await signQuote(lp.provider!, callPool.address, quote);

      await expect(
        callPool
          .connect(trader)
          .fillQuote(quote, quote.size, sig.v, sig.r, sig.s),
      ).to.be.revertedWithCustomError(callPool, 'Pool__OutOfBoundsPrice');
    });

    it('should revert if quote is not used by someone else than taker', async () => {
      const quote = await getTradeQuote();

      const sig = await signQuote(lp.provider!, callPool.address, quote);

      await expect(
        callPool
          .connect(deployer)
          .fillQuote(quote, quote.size, sig.v, sig.r, sig.s),
      ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidQuoteTaker');
    });

    it('should revert if nonce is not the current one', async () => {
      const quote = await getTradeQuote();

      await callPool.setNonce(trader.address, 2);

      let sig = await signQuote(lp.provider!, callPool.address, { ...quote });

      await expect(
        callPool
          .connect(trader)
          .fillQuote(quote, quote.size, sig.v, sig.r, sig.s),
      ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidQuoteNonce');

      sig = await signQuote(lp.provider!, callPool.address, {
        ...quote,
        nonce: 10,
      });

      await expect(
        callPool
          .connect(trader)
          .fillQuote(quote, quote.size, sig.v, sig.r, sig.s),
      ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidQuoteNonce');
    });

    it('should revert if signed message does not match quote', async () => {
      const quote = await getTradeQuote();

      const sig = await signQuote(lp.provider!, callPool.address, quote);

      await expect(
        callPool
          .connect(trader)
          .fillQuote(
            { ...quote, size: BigNumber.from(quote.size).mul(2).toString() },
            quote.size,
            sig.v,
            sig.r,
            sig.s,
          ),
      ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidQuoteSignature');
    });
  });

  describe('#formatTokenId', () => {
    it('should properly format token id', async () => {
      const operator = '0x1000000000000000000000000000000000000001';
      const tokenId = await callPool.formatTokenId(
        operator,
        parseEther('0.001'),
        parseEther('1'),
        OrderType.LC,
      );

      console.log(tokenId.toHexString());

      expect(tokenId.mask(10)).to.eq(1);
      expect(tokenId.shr(10).mask(10)).to.eq(1000);
      expect(tokenId.shr(20).mask(160)).to.eq(operator);
      expect(tokenId.shr(180).mask(4)).to.eq(2);
      expect(tokenId.shr(252).mask(4)).to.eq(1);
    });
  });

  describe('#parseTokenId', () => {
    it('should properly parse token id', async () => {
      const r = await callPool.parseTokenId(
        BigNumber.from(
          '0x10000000000000000021000000000000000000000000000000000000001fa001',
        ),
      );

      expect(r.lower).to.eq(parseEther('0.001'));
      expect(r.upper).to.eq(parseEther('1'));
      expect(r.operator).to.eq('0x1000000000000000000000000000000000000001');
      expect(r.orderType).to.eq(OrderType.LC);
      expect(r.version).to.eq(1);
    });
  });
});
