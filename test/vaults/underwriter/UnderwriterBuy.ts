import { expect } from 'chai';
import { ethers } from 'hardhat';
import {
  ERC20Mock,
  ERC20Mock__factory,
  UnderwriterVaultMock,
  UnderwriterVaultMock__factory,
  UnderwriterVaultProxy__factory,
  UnderwriterVaultProxy,
} from '../../../typechain';
import { PoolUtil } from '../../../utils/PoolUtil';
import {
  parseEther,
  parseUnits,
  formatEther,
  formatUnits,
} from 'ethers/lib/utils';
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

describe('UnderwriterVault', () => {
  let deployer: SignerWithAddress;
  let trader: SignerWithAddress;
  let lp: SignerWithAddress;

  let pool: PoolUtil;
  let vaultImpl: UnderwriterVaultMock;
  let vaultProxy: UnderwriterVaultProxy;
  let vault: UnderwriterVaultMock;

  let base: ERC20Mock;
  let quote: ERC20Mock;

  let baseOracle: MockContract;
  let volOracle: MockContract;

  const log = true;

  before(async () => {
    [deployer, trader, lp] = await ethers.getSigners();

    base = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
    quote = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

    await base.deployed();
    await quote.deployed();

    await base.mint(trader.address, parseEther('1000'));
    await quote.mint(trader.address, parseEther('1000000'));

    await base.mint(lp.address, parseEther('1000'));
    await quote.mint(lp.address, parseEther('1000000'));

    await base.mint(deployer.address, parseEther('1000'));
    await quote.mint(deployer.address, parseEther('1000000'));

    baseOracle = await deployMockContract(deployer as any, [
      'function latestAnswer() external view returns (int256)',
      'function decimals () external view returns (uint8)',
    ]);

    await baseOracle.mock.latestAnswer.returns(parseUnits('1500', 8));
    await baseOracle.mock.decimals.returns(8);

    volOracle = await deployMockContract(deployer as any, [
      'function getVolatility(address, uint256, uint256, uint256) external view returns (int256)',
    ]);
    await volOracle.mock.getVolatility.returns(parseUnits('1'));

    pool = await PoolUtil.deploy(
      deployer,
      base.address,
      baseOracle.address,
      deployer.address,
      parseEther('0.1'), // 10%
      true,
      true,
    );

    vaultImpl = await new UnderwriterVaultMock__factory(deployer).deploy(
      volOracle.address,
      pool.poolFactory.address,
    );
    await vaultImpl.deployed();

    if (log)
      console.log(`UnderwriterVault Implementation : ${vaultImpl.address}`);

    vaultProxy = await new UnderwriterVaultProxy__factory(deployer).deploy(
      vaultImpl.address,
      base.address,
      quote.address,
      baseOracle.address,
      'WETH Vault',
      'WETH',
      true,
    );
    await vaultProxy.deployed();

    vault = UnderwriterVaultMock__factory.connect(vaultProxy.address, deployer);

    if (log) console.log(`UnderwriterVaultProxy : ${vaultProxy.address}`);
  });

  describe('#setting up the environment', () => {
    it('responds to basic funciton call', async () => {
      const assetAmount = parseEther('2');
      const shareAmount = await vault.convertToShares(assetAmount);
      expect(shareAmount).to.eq(assetAmount);
    });
  });

  describe('#buy functionality', () => {
    it('responds to mock IV oracle query', async () => {
      const iv = await volOracle.getVolatility(
        base.address,
        parseEther('2500'),
        parseEther('2000'),
        parseEther('0.2'),
      );
      expect(parseFloat(formatEther(iv))).to.eq(1);
    });
    it('responds to mock BASE oracle query', async () => {
      const price = await baseOracle.latestAnswer();
      expect(parseFloat(formatUnits(price, 8))).to.eq(1500);
    });
  });
});
