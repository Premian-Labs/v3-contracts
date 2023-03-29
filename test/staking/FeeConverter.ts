import {
  ERC20Mock__factory,
  ExchangeHelper__factory,
  FeeConverter,
  FeeConverter__factory,
  ProxyUpgradeableOwnable__factory,
  VxPremia__factory,
  VxPremiaProxy__factory,
} from '../../typechain';
import { bnToNumber } from '../../utils/sdk/math';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { parseEther } from 'ethers/lib/utils';
import { ethers } from 'hardhat';

describe('FeeConverter', () => {
  async function deploy() {
    const [deployer, user1, treasury] = await ethers.getSigners();

    const exchangeHelper = await new ExchangeHelper__factory(deployer).deploy();

    const usdc = await new ERC20Mock__factory(deployer).deploy('USDC', 8);
    const premia = await new ERC20Mock__factory(deployer).deploy('PREMIA', 18);

    const vxPremiaImpl = await new VxPremia__factory(deployer).deploy(
      ethers.constants.AddressZero,
      ethers.constants.AddressZero,
      premia.address,
      usdc.address,
      exchangeHelper.address,
    );
    const vxPremiaProxy = await new VxPremiaProxy__factory(deployer).deploy(
      vxPremiaImpl.address,
    );
    const vxPremia = VxPremia__factory.connect(vxPremiaProxy.address, deployer);

    const feeConverterImpl = await new FeeConverter__factory(deployer).deploy(
      exchangeHelper.address,
      usdc.address,
      vxPremia.address,
      treasury.address,
    );
    const feeConverterProxy = await new ProxyUpgradeableOwnable__factory(
      deployer,
    ).deploy(feeConverterImpl.address);
    const feeConverter = FeeConverter__factory.connect(
      feeConverterProxy.address,
      deployer,
    );

    return {
      deployer,
      user1,
      treasury,
      exchangeHelper,
      feeConverter,
      vxPremia,
      usdc,
      premia,
    };
  }

  it('should fail to call convert if not authorized', async () => {
    const { feeConverter, usdc } = await loadFixture(deploy);

    await expect(
      feeConverter.convert(
        usdc.address,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        '0x',
      ),
    ).to.be.revertedWithCustomError(
      feeConverter,
      'FeeConverter__NotAuthorized',
    );
  });

  it('should convert fees successfully', async () => {
    // ToDo : Update to use fork mode
    // await p.feeConverter.setAuthorized(deployer.address, true);
    //
    // await depositUniswapLiquidity(
    //   user1,
    //   uniswap.weth.address,
    //   rewardTokenWeth,
    //   (await rewardTokenWeth.token0()) == uniswap.weth.address
    //     ? parseEther('1')
    //     : parseEther('10000'),
    //   (await rewardTokenWeth.token1()) == uniswap.weth.address
    //     ? parseEther('1')
    //     : parseEther('10000'),
    // );
    //
    // await depositUniswapLiquidity(
    //   user1,
    //   uniswap.weth.address,
    //   uniswap.daiWeth,
    //   (await uniswap.daiWeth.token0()) == uniswap.weth.address
    //     ? parseEther('1')
    //     : parseEther('100'),
    //   (await uniswap.daiWeth.token1()) == uniswap.weth.address
    //     ? parseEther('1')
    //     : parseEther('100'),
    // );
    //
    // const amount = parseEther('10');
    // await uniswap.dai.mint(p.feeConverter.address, amount);
    //
    // const uniswapPath = [
    //   uniswap.dai.address,
    //   uniswap.weth.address,
    //   p.rewardToken.address,
    // ];
    //
    // const { timestamp } = await ethers.provider.getBlock('latest');
    //
    // const iface = new ethers.utils.Interface(uniswapABIs);
    // const data = iface.encodeFunctionData('swapExactTokensForTokens', [
    //   amount,
    //   amount.mul(2),
    //   uniswapPath,
    //   exchangeHelper.address,
    //   timestamp + 86400,
    // ]);
    //
    // await p.feeConverter.convert(
    //   uniswap.dai.address,
    //   uniswap.router.address,
    //   uniswap.router.address,
    //   data,
    // );
    //
    // expect(bnToNumber(await p.rewardToken.balanceOf(treasury.address))).to.eq(
    //   165.79,
    // );
    // expect(await uniswap.dai.balanceOf(p.feeConverter.address)).to.eq(0);
    // expect(bnToNumber(await p.rewardToken.balanceOf(p.vxPremia.address))).to.eq(
    //   663.16,
    // );
    //
    // expect(bnToNumber((await p.vxPremia.getAvailableRewards())[0])).to.eq(
    //   663.16,
    // );
  });

  it('should make premia successfully with WETH', async () => {
    // ToDo : Update to use fork mode
    // await p.feeConverter.setAuthorized(deployer.address, true);
    //
    // await depositUniswapLiquidity(
    //   user1,
    //   uniswap.weth.address,
    //   rewardTokenWeth,
    //   (await rewardTokenWeth.token0()) == uniswap.weth.address
    //     ? parseEther('1')
    //     : parseEther('10000'),
    //   (await rewardTokenWeth.token1()) == uniswap.weth.address
    //     ? parseEther('1')
    //     : parseEther('10000'),
    // );
    //
    // await depositUniswapLiquidity(
    //   user1,
    //   uniswap.weth.address,
    //   uniswap.daiWeth,
    //   (await uniswap.daiWeth.token0()) == uniswap.weth.address
    //     ? parseEther('1')
    //     : parseEther('100'),
    //   (await uniswap.daiWeth.token1()) == uniswap.weth.address
    //     ? parseEther('1')
    //     : parseEther('100'),
    // );
    //
    // const amount = parseEther('10');
    // await uniswap.weth.deposit({ value: amount });
    // await uniswap.weth.transfer(p.feeConverter.address, amount);
    //
    // const uniswapPath = [uniswap.weth.address, p.rewardToken.address];
    //
    // const { timestamp } = await ethers.provider.getBlock('latest');
    //
    // const iface = new ethers.utils.Interface(uniswapABIs);
    // const data = iface.encodeFunctionData('swapExactTokensForTokens', [
    //   amount,
    //   amount.mul(2),
    //   uniswapPath,
    //   exchangeHelper.address,
    //   timestamp + 86400,
    // ]);
    //
    // await p.feeConverter.convert(
    //   uniswap.weth.address,
    //   uniswap.router.address,
    //   uniswap.router.address,
    //   data,
    // );
    //
    // expect(bnToNumber(await p.rewardToken.balanceOf(treasury.address))).to.eq(
    //   1817.68,
    // );
    // expect(await uniswap.weth.balanceOf(p.feeConverter.address)).to.eq(0);
    // expect(bnToNumber(await p.rewardToken.balanceOf(p.vxPremia.address))).to.eq(
    //   7270.73,
    // );
    // expect(bnToNumber((await p.vxPremia.getAvailableRewards())[0])).to.eq(
    //   7270.73,
    // );
  });

  it('should send USDC successfully to vxPremia', async () => {
    const { feeConverter, usdc, deployer, treasury, vxPremia } =
      await loadFixture(deploy);

    await feeConverter.connect(deployer).setAuthorized(deployer.address, true);

    await usdc.mint(feeConverter.address, parseEther('10'));
    await feeConverter.convert(
      usdc.address,
      ethers.constants.AddressZero,
      ethers.constants.AddressZero,
      '0x',
    );

    expect(await usdc.balanceOf(treasury.address)).to.eq(parseEther('5'));
    expect(await usdc.balanceOf(feeConverter.address)).to.eq(0);
    expect(await usdc.balanceOf(vxPremia.address)).to.eq(parseEther('5'));
    expect(bnToNumber((await vxPremia.getAvailableRewards())[0])).to.eq(5);
  });
});
