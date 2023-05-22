import { getCurrentTimestamp } from 'hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp';
import moment from 'moment-timezone';

moment.tz.setDefault('UTC');

export const ONE_HOUR = 3600;
export const ONE_DAY = 24 * ONE_HOUR;
export const ONE_WEEK = 7 * ONE_DAY;
export const ONE_MONTH = 30 * ONE_DAY;
export const ONE_YEAR = 365 * ONE_DAY;

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

export async function getValidMaturity(interval: any, period: string) {
  const timestamp = getCurrentTimestamp();
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
