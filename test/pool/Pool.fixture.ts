import { parseEther, parseUnits } from 'ethers/lib/utils';
import { OrderType } from '../../utils/sdk/types';
import { BigNumber } from 'ethers';
import { ONE_ETHER } from '../../utils/constants';
import { average, scaleDecimals as _scaleDecimals } from '../../utils/sdk/math';
import { ethers } from 'hardhat';
import { ERC20Mock__factory, IPoolMock__factory } from '../../typechain';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import { PoolUtil } from '../../utils/PoolUtil';
import { tokens } from '../../utils/addresses';
import { getValidMaturity, latest, ONE_HOUR } from '../../utils/time';

export const depositFnSig =
  'deposit((address,address,uint256,uint256,uint8),uint256,uint256,uint256,uint256,uint256,(address,uint256,uint256,uint256,bytes))';

export const strike = parseEther('1200');
export const protocolFeePercentage = 0.5;

export function getSettlementPrice(isCall: boolean, isItm: boolean) {
  if (isCall) {
    return isItm ? parseEther('1300') : parseEther('1150');
  }

  return isItm ? parseEther('1150') : parseEther('1300');
}

//////////////////////////////////////////////////////
//////////////////////////////////////////////////////

export function runCallAndPutTests(tests: (isCallPool: boolean) => void) {
  describe('Call', () => {
    tests(true);
  });

  describe('Put', () => {
    tests(false);
  });
}

//////////////////////////////////////////////////////
//////////////////////////////////////////////////////

export async function deploy_CALL() {
  return _deploy(true);
}

export async function deploy_PUT() {
  return _deploy(false);
}

async function _deploy(isCall: boolean) {
  const [deployer, lp, trader, feeReceiver] = await ethers.getSigners();

  const base = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
  const quote = await new ERC20Mock__factory(deployer).deploy('USDC', 6);
  const poolToken = isCall ? base : quote;
  const poolTokenDecimals = isCall ? 18 : 6;

  const oracleAdapter = await deployMockContract(deployer as any, [
    'function quote(address,address) external view returns (uint256)',
    'function quoteFrom(address,address,uint256) external view returns (uint256)',
    'function upsertPair(address,address) external',
  ]);

  await oracleAdapter.mock.quote.returns(parseUnits('1000', 18));
  await oracleAdapter.mock.quoteFrom.returns(parseUnits('1000', 18));
  await oracleAdapter.mock.upsertPair.returns();

  const p = await PoolUtil.deploy(
    deployer,
    tokens.WETH.address,
    oracleAdapter.address,
    feeReceiver.address,
    parseEther('0.1'), // 10%
    false,
    true,
  );

  const maturity = await getValidMaturity(10, 'months');

  const deployPool = async (isCallPool: boolean) => {
    const tx = await p.poolFactory.deployPool(
      {
        base: base.address,
        quote: quote.address,
        oracleAdapter: oracleAdapter.address,
        strike,
        maturity,
        isCallPool,
      },
      {
        value: parseEther('1'),
      },
    );

    const r = await tx.wait(1);
    const poolAddress = (r as any).events[0].args.poolAddress;

    return IPoolMock__factory.connect(poolAddress, deployer);
  };

  const pool = await deployPool(isCall);

  const getTradeQuote = async () => {
    const timestamp = BigNumber.from(await latest());
    return {
      provider: lp.address,
      taker: ethers.constants.AddressZero,
      price: parseEther('0.1'),
      size: parseEther('10'),
      isBuy: false,
      deadline: timestamp.add(ONE_HOUR),
      salt: timestamp,
    };
  };

  const contractsToCollateral = (size: BigNumber) => {
    return isCall ? size : size.mul(strike).div(ONE_ETHER);
  };

  const scaleDecimals = (amount: BigNumber) => {
    return _scaleDecimals(amount, poolTokenDecimals);
  };

  const pKey = {
    owner: lp.address,
    operator: lp.address,
    lower: parseEther('0.1'),
    upper: parseEther('0.3'),
    orderType: OrderType.LC,
  } as const;
  Object.freeze(pKey);

  return {
    deployer,
    lp,
    trader,
    feeReceiver,
    pool,
    ...p,
    base,
    quote,
    oracleAdapter,
    maturity,
    pKey,
    poolToken,
    poolTokenDecimals,
    getTradeQuote,
    contractsToCollateral,
    scaleDecimals,
  };
}

//////////////////////////////////////////////////////
//////////////////////////////////////////////////////

export async function deployAndMintForLP_CALL() {
  return _deployAndMintForLP(true);
}

export async function deployAndMintForLP_PUT() {
  return _deployAndMintForLP(false);
}

async function _deployAndMintForLP(isCall: boolean) {
  const f = await _deploy(isCall);

  let initialCollateral = parseEther('1000');
  if (!isCall) {
    initialCollateral = initialCollateral.mul(strike).div(ONE_ETHER);
  }

  initialCollateral = f.scaleDecimals(initialCollateral);

  const token = isCall ? f.base : f.quote;

  await token.mint(f.lp.address, initialCollateral);
  await token.connect(f.lp).approve(f.router.address, initialCollateral);

  return { ...f, initialCollateral };
}

//////////////////////////////////////////////////////
//////////////////////////////////////////////////////

export async function deployAndMintForTraderAndLP_CALL() {
  return _deployAndMintForTraderAndLP(true);
}

export async function deployAndMintForTraderAndLP_PUT() {
  return _deployAndMintForTraderAndLP(false);
}

async function _deployAndMintForTraderAndLP(isCall: boolean) {
  const f = await _deploy(isCall);

  let initialCollateral = parseEther('10');
  if (!isCall) {
    initialCollateral = initialCollateral.mul(strike).div(ONE_ETHER);
  }

  initialCollateral = f.scaleDecimals(initialCollateral);

  const token = isCall ? f.base : f.quote;

  for (const user of [f.lp, f.trader]) {
    await token.mint(user.address, initialCollateral);
    await token.connect(user).approve(f.router.address, initialCollateral);
  }

  return { ...f, initialCollateral };
}

//////////////////////////////////////////////////////
//////////////////////////////////////////////////////

async function deposit(
  f: Awaited<ReturnType<typeof _deployAndMintForTraderAndLP>>,
  orderType: OrderType,
  depositSize: BigNumber,
) {
  const pKey = { ...f.pKey, orderType } as const;
  Object.freeze(pKey);

  const tokenId = await f.pool.formatTokenId(
    pKey.operator,
    pKey.lower,
    pKey.upper,
    pKey.orderType,
  );

  const nearestBelow = await f.pool.getNearestTicksBelow(
    pKey.lower,
    pKey.upper,
  );

  await f.pool
    .connect(f.lp)
    [depositFnSig](
      pKey,
      nearestBelow.nearestBelowLower,
      nearestBelow.nearestBelowUpper,
      depositSize,
      0,
      parseEther('1'),
      emptyPermit2,
    );

  return { ...f, tokenId, pKey, depositSize };
}

//////////////////////////////////////////////////////
//////////////////////////////////////////////////////

export async function deployAndDeposit_1000_CS_CALL() {
  return _deployAndDeposit_1000_CS(true);
}

export async function deployAndDeposit_1000_CS_PUT() {
  return _deployAndDeposit_1000_CS(false);
}

async function _deployAndDeposit_1000_CS(isCall: boolean) {
  return deposit(
    await _deployAndMintForLP(isCall),
    OrderType.CS,
    parseEther('1000'),
  );
}

//////////////////////////////////////////////////////
//////////////////////////////////////////////////////
export async function deployAndDeposit_1_CS_CALL() {
  return _deployAndDeposit_1_CS(true);
}

export async function deployAndDeposit_1_CS_PUT() {
  return _deployAndDeposit_1_CS(false);
}

async function _deployAndDeposit_1_CS(isCall: boolean) {
  return deposit(await _deployAndMintForLP(isCall), OrderType.CS, ONE_ETHER);
}

//////////////////////////////////////////////////////
//////////////////////////////////////////////////////

export async function deployAndDeposit_1000_LC_CALL() {
  return _deployAndDeposit_1000_LC(true);
}

export async function deployAndDeposit_1000_LC_PUT() {
  return _deployAndDeposit_1000_LC(false);
}

async function _deployAndDeposit_1000_LC(isCall: boolean) {
  return deposit(
    await _deployAndMintForLP(isCall),
    OrderType.LC,
    parseEther('1000'),
  );
}

//////////////////////////////////////////////////////
//////////////////////////////////////////////////////
export async function deployAndDeposit_1_LC_CALL() {
  return _deployAndDeposit_1_LC(true);
}

export async function deployAndDeposit_1_LC_PUT() {
  return _deployAndDeposit_1_LC(false);
}

async function _deployAndDeposit_1_LC(isCall: boolean) {
  return deposit(await _deployAndMintForLP(isCall), OrderType.LC, ONE_ETHER);
}

//////////////////////////////////////////////////////
//////////////////////////////////////////////////////
export async function deployAndBuy_CALL() {
  return _deployAndBuy(true);
}

export async function deployAndBuy_PUT() {
  return _deployAndBuy(false);
}

async function _deployAndBuy(isCall: boolean) {
  const f = await _deployAndDeposit_1_CS(isCall);

  const tradeSize = ONE_ETHER;
  const price = f.pKey.lower;
  const nextPrice = f.pKey.upper;
  const avgPrice = average(price, nextPrice);
  const takerFee = await f.pool.takerFee(
    tradeSize,
    f.scaleDecimals(tradeSize.mul(avgPrice).div(ONE_ETHER)),
    true,
  );
  const totalPremium = await f.pool.getTradeQuote(tradeSize, true);

  const token = isCall ? f.base : f.quote;

  await token.mint(f.trader.address, totalPremium);
  await token.connect(f.trader).approve(f.router.address, totalPremium);

  const collateral = f.scaleDecimals(isCall ? ONE_ETHER : strike);

  await f.pool
    .connect(f.trader)
    .trade(tradeSize, true, totalPremium, emptyPermit2);

  const protocolFees = await f.pool.protocolFees();

  return {
    ...f,
    tradeSize,
    price,
    nextPrice,
    avgPrice,
    takerFee,
    totalPremium,
    protocolFees,
    collateral,
  };
}

//////////////////////////////////////////////////////
//////////////////////////////////////////////////////
export async function deployAndSell_CALL() {
  return _deployAndSell(true);
}

export async function deployAndSell_PUT() {
  return _deployAndSell(false);
}

async function _deployAndSell(isCall: boolean) {
  const f = await _deployAndDeposit_1_LC(isCall);

  const tradeSize = ONE_ETHER;
  const price = f.pKey.upper;
  const nextPrice = f.pKey.lower;
  const avgPrice = average(price, nextPrice);
  const takerFee = await f.pool.takerFee(
    tradeSize,
    f.scaleDecimals(tradeSize.mul(avgPrice).div(ONE_ETHER)),
    true,
  );

  const totalPremium = await f.pool.getTradeQuote(tradeSize, false);

  const token = isCall ? f.base : f.quote;

  let mintAmount = parseUnits('1', f.poolTokenDecimals);
  if (!isCall) {
    mintAmount = mintAmount.mul(strike).div(ONE_ETHER);
  }

  await token.mint(f.trader.address, mintAmount);
  await token.connect(f.trader).approve(f.router.address, mintAmount);

  const collateral = f.scaleDecimals(isCall ? ONE_ETHER : strike);

  await f.pool
    .connect(f.trader)
    .trade(tradeSize, false, totalPremium, emptyPermit2);

  const protocolFees = await f.pool.protocolFees();

  return {
    ...f,
    tradeSize,
    price,
    nextPrice,
    avgPrice,
    takerFee,
    totalPremium,
    protocolFees,
    collateral,
  };
}
