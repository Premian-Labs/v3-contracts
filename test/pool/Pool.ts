import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  PoolMock,
  PoolMock__factory,
  Premia,
  Premia__factory,
} from '../../typechain';
import { diamondCut } from '../../scripts/utils/diamond';
import { BigNumber } from 'ethers';
import { parseEther } from 'ethers/lib/utils';

describe('Pool', () => {
  let admin: SignerWithAddress;
  let poolDiamond: Premia;
  let pool: PoolMock;

  let snapshotId: number;

  before(async () => {
    [admin] = await ethers.getSigners();

    poolDiamond = await new Premia__factory(admin).deploy();

    const poolFactory = new PoolMock__factory(admin);
    const poolImpl = await poolFactory.deploy();

    let registeredSelectors = [
      poolDiamond.interface.getSighash('supportsInterface(bytes4)'),
    ];

    registeredSelectors = registeredSelectors.concat(
      await diamondCut(
        poolDiamond,
        poolImpl.address,
        poolFactory,
        registeredSelectors,
      ),
    );

    pool = PoolMock__factory.connect(poolDiamond.address, admin);
  });

  beforeEach(async () => {
    snapshotId = await ethers.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await ethers.provider.send('evm_revert', [snapshotId]);
  });

  describe('#formatTokenId', () => {
    it('should properly format token id', async () => {
      const operator = '0x1000000000000000000000000000000000000001';
      const tokenId = await pool.formatTokenId(
        operator,
        parseEther('0.001'),
        parseEther('1'),
        3,
      );

      console.log(tokenId.toHexString());

      expect(tokenId.mask(10)).to.eq(1);
      expect(tokenId.shr(10).mask(10)).to.eq(1000);
      expect(tokenId.shr(20).mask(160)).to.eq(operator);
      expect(tokenId.shr(180).mask(4)).to.eq(3);
      expect(tokenId.shr(184).mask(4)).to.eq(1);
    });
  });

  describe('#parseTokenId', () => {
    it('should properly parse token id', async () => {
      const r = await pool.parseTokenId(
        BigNumber.from('0x0131000000000000000000000000000000000000001fa001'),
      );

      expect(r.lower).to.eq(parseEther('0.001'));
      expect(r.upper).to.eq(parseEther('1'));
      expect(r.operator).to.eq('0x1000000000000000000000000000000000000001');
      expect(r.orderType).to.eq(3);
      expect(r.version).to.eq(1);
    });
  });

  describe('#amountOfTicksBetween', () => {
    it('should correctly calculate amount of ticks between two values', async () => {
      for (const el of [
        [parseEther('0.001'), parseEther('1'), 999],
        [parseEther('0.05'), parseEther('0.95'), 900],
        [parseEther('0.49'), parseEther('0.491'), 1],
      ])
        expect(await pool.amountOfTicksBetween(el[0], el[1])).to.eq(el[2]);
    });

    it('should revert if lower >= upper', async () => {
      for (const el of [
        [parseEther('0.2'), parseEther('0.01')],
        [parseEther('0.1'), parseEther('0.1')],
      ])
        await expect(
          pool.amountOfTicksBetween(el[0], el[1]),
        ).to.be.revertedWithCustomError(
          pool,
          'Pricing__UpperNotGreaterThanLower',
        );
    });
  });
});
