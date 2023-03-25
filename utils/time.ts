import { network } from 'hardhat';

import {
  SnapshotRestorer,
  takeSnapshot,
  time,
  reset,
} from '@nomicfoundation/hardhat-network-helpers';

import moment from 'moment-timezone';
import { NumberLike } from '@nomicfoundation/hardhat-network-helpers/dist/src/types';
import { getCurrentTimestamp } from 'hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp';

moment.tz.setDefault('UTC');

export const ONE_HOUR = 3600;
export const ONE_DAY = 24 * ONE_HOUR;
export const ONE_WEEK = 7 * ONE_DAY;
export const ONE_MONTH = 30 * ONE_DAY;
export const ONE_YEAR = 365 * ONE_DAY;

// returns the current timestamp
export async function latest() {
  return time.latest();
}

// Increases ganache time by the passed duration in seconds
export async function increase(duration: NumberLike) {
  return time.increase(duration);
}

/**
 * Beware that due to the need of calling two separate ganache methods and rpc calls overhead
 * it's hard to increase time precisely to a target point so design your test to tolerate
 * small fluctuations from time to time.
 *
 * @param target time in seconds
 */
export async function increaseTo(target: NumberLike) {
  return time.increaseTo(target);
}

export function weekOfMonth(timestamp: number) {
  const firstDayOfMonth = moment.unix(timestamp).clone().startOf('month');
  const firstDayOfWeek = firstDayOfMonth.clone().startOf('week');

  const offset = firstDayOfMonth.diff(firstDayOfWeek, 'days');

  return Math.ceil((moment.unix(timestamp).date() + offset) / 7);
}

export async function getLastFridayOfMonth(timestamp: number, interval: any) {
  const currentTime = moment.unix(timestamp);

  const lastDayOfMonth = moment(currentTime.add(interval, 'months'))
    .endOf('month')
    .startOf('day');

  let friday;

  if (lastDayOfMonth.day() == 6) {
    friday = lastDayOfMonth.subtract(1, 'days');
  } else {
    friday = lastDayOfMonth.subtract(lastDayOfMonth.day() + 2, 'days');
  }

  return friday.hour(8).unix();
}

export async function getValidMaturity(
  interval: any,
  period: string,
  isDevMode = true,
) {
  const timestamp = isDevMode ? await time.latest() : getCurrentTimestamp();
  const currentTime = moment.unix(timestamp);

  if (period === 'days' && interval < 3) {
    return moment(currentTime.add(interval, 'days'))
      .startOf('day')
      .hour(8)
      .unix();
  } else if (period === 'weeks' && interval <= 4) {
    return moment(currentTime.add(interval, 'weeks'))
      .startOf('isoWeek')
      .day('friday')
      .hour(8)
      .unix();
  } else if (period === 'months' && interval <= 12) {
    return await getLastFridayOfMonth(timestamp, interval);
  }

  throw new Error('Invalid Maturity Parameters');
}

export function revertToSnapshotAfterEach(
  beforeEachCallback = async () => {},
  afterEachCallback = async () => {},
) {
  let snapshot: SnapshotRestorer;

  beforeEach(async function () {
    snapshot = await takeSnapshot();
    await beforeEachCallback.bind(this)();
  });
  afterEach(async () => {
    await afterEachCallback.bind(this)();
    await snapshot.restore();
  });
}

export async function setHardhat(jsonRpcUrl: string, blockNumber: number) {
  await reset(jsonRpcUrl, blockNumber);
}

export async function resetHardhat() {
  if ((network as any).config.forking) {
    const { url: jsonRpcUrl, blockNumber } = (network as any).config.forking;
    await setHardhat(jsonRpcUrl, blockNumber);
  } else {
    await reset();
  }
}
