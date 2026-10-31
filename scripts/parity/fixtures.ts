// Expected outputs of the Electron app's shared TypeScript (the reference
// the Swift port must match), written as the fixture the MillisalaryCore
// parity tests read. Bundled and run by scripts/parity/generate-fixtures.sh;
// `@shared` and `@renderer` are the Electron repo's src/shared and
// src/renderer/src.
import { writeFileSync } from 'node:fs'
import dayjs from 'dayjs'
import {
  withEndHour,
  withPayday,
  withStartHour,
  withWorkingDays,
  withWorkingHoursPerDay,
  type SettingsValues,
} from '@renderer/utils/settingsDraft'
import {
  calculateEarnings,
  formatCurrency,
  formatCurrencyParts,
  getPaydayInMonth,
  getWorkingWindow,
  isScheduledDay,
} from '@shared/calculations'
import {
  formatTimeInputValue,
  normalizePayday,
  normalizeWorkingDays,
  normalizeWorkingHoursPerDay,
  parseTimeInputValue,
} from '@shared/salaryForm'
import { getScheduledNotifications } from '@shared/notifications'
import { sanitizeSettings } from '@shared/settings'

const [outputPath, reference] = process.argv.slice(2)

const TIME_ZONES = ['Europe/Kyiv', 'America/New_York', 'Asia/Kolkata']

interface Schedule {
  monthlySalary: number
  workingDays: number
  workingHoursPerDay: number
  startHour: string
  endHour: string
  payday: number
  exchangeRate: number
}

const OFFICE: Schedule = {
  monthlySalary: 54321,
  workingDays: 22,
  workingHoursPerDay: 8,
  startHour: '09:00',
  endHour: '17:00',
  payday: 1,
  exchangeRate: 1,
}

const SCHEDULES: Record<string, Schedule> = {
  office: OFFICE,
  converted: {
    ...OFFICE,
    monthlySalary: 3000,
    workingDays: 21,
    startHour: '10:00',
    endHour: '19:00',
    payday: 5,
    exchangeRate: 41.37,
  },
  overnight: { ...OFFICE, startHour: '22:00', endHour: '06:00', payday: 15 },
  crossesMidnight: { ...OFFICE, startHour: '23:30', endHour: '00:15' },
  noEnd: { ...OFFICE, startHour: '10:00', endHour: '', workingHoursPerDay: 7.5 },
  noTimes: { ...OFFICE, startHour: '', endHour: '', workingHoursPerDay: 6 },
  sameTimes: { ...OFFICE, startHour: '09:00', endHour: '09:00' },
  fractionalHoursNoEnd: { ...OFFICE, endHour: '', workingHoursPerDay: 8.33 },
  fractionalHoursSameTimes: {
    ...OFFICE,
    endHour: '09:00',
    workingHoursPerDay: 8.33,
  },
  eveningNoEnd: {
    ...OFFICE,
    startHour: '20:00',
    endHour: '',
    workingHoursPerDay: 9.5,
  },
  fewDays: { ...OFFICE, workingDays: 10, payday: 31 },
  allDay: {
    ...OFFICE,
    workingDays: 31,
    workingHoursPerDay: 24,
    startHour: '00:00',
    endHour: '',
    payday: 30,
  },
  fractionalDays: { ...OFFICE, workingDays: 21.5, payday: 29 },
  shortShift: {
    ...OFFICE,
    startHour: '12:00',
    endHour: '',
    workingHoursPerDay: 0.5,
  },
  unpaid: { ...OFFICE, monthlySalary: 0 },
}

// Local wall-clock instants [year, month (1-12), day, hour, minute, second,
// ms], read in each time zone: working hours, both edges of the window,
// weekends, month and year ends, leap day, paydays and the DST weekends of
// Kyiv and New York
const LOCAL_INSTANTS: number[][] = [
  [2026, 10, 29, 0, 0, 0, 0],
  [2026, 10, 29, 5, 59, 59, 999],
  [2026, 10, 29, 8, 59, 59, 999],
  [2026, 10, 29, 9, 0, 0, 0],
  [2026, 10, 29, 9, 0, 0, 1],
  [2026, 10, 29, 12, 34, 56, 789],
  [2026, 10, 29, 16, 59, 59, 999],
  [2026, 10, 29, 17, 0, 0, 0],
  [2026, 10, 29, 21, 0, 0, 0],
  [2026, 10, 29, 23, 59, 59, 999],
  [2026, 10, 30, 18, 30, 0, 0],
  [2026, 10, 31, 12, 0, 0, 0],
  [2026, 11, 1, 10, 0, 0, 0],
  [2026, 11, 2, 9, 30, 0, 0],
  [2026, 3, 27, 23, 0, 0, 0],
  [2026, 3, 28, 2, 0, 0, 0],
  [2026, 3, 29, 3, 30, 0, 0],
  [2026, 3, 30, 11, 0, 0, 0],
  [2026, 3, 8, 12, 0, 0, 0],
  [2026, 3, 9, 8, 0, 0, 0],
  [2026, 10, 24, 5, 0, 0, 0],
  [2026, 10, 25, 3, 30, 0, 0],
  [2026, 10, 26, 10, 0, 0, 0],
  [2026, 2, 27, 15, 0, 0, 0],
  [2026, 2, 28, 11, 0, 0, 0],
  [2026, 3, 2, 10, 0, 0, 0],
  [2026, 1, 1, 10, 0, 0, 0],
  [2026, 12, 31, 16, 0, 0, 0],
  [2027, 1, 1, 9, 15, 0, 0],
  [2028, 2, 28, 7, 0, 0, 0],
  [2028, 2, 29, 13, 0, 0, 0],
  [2026, 6, 30, 17, 30, 0, 0],
  [2026, 7, 1, 6, 0, 0, 0],
  [2026, 11, 30, 10, 0, 0, 0],
  [2026, 4, 30, 12, 0, 0, 0],
  [2026, 5, 15, 12, 0, 0, 0],
  [2026, 5, 29, 12, 0, 0, 0],
  [2026, 5, 31, 12, 0, 0, 0],
]

// Plus instants spread over 2026-2028 by a fixed-seed generator, so the
// fixture doesn't change between runs
const randomInstants = (count: number) => {
  let seed = 20261031
  const next = () => {
    seed = (seed * 1103515245 + 12345) % 2 ** 31
    return seed / 2 ** 31
  }
  const from = Date.UTC(2026, 0, 1)
  const to = Date.UTC(2029, 0, 1)

  return Array.from({ length: count }, () =>
    Math.floor(from + next() * (to - from))
  )
}

const RANDOM_INSTANTS = randomInstants(20)

// Node resets its zone cache when TZ is assigned; every expected value
// depends on that, so check the local clock really moved
const setTimeZone = (timeZone: string) => {
  process.env.TZ = timeZone
  const probe = new Date(Date.UTC(2026, 6, 15, 12, 0))
  const hour = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour: 'numeric',
    hourCycle: 'h23',
  }).format(probe)

  if (probe.getHours() !== Number(hour)) {
    throw new Error(`TZ=${timeZone} did not take effect`)
  }
}

const earnings: unknown[] = []

for (const timeZone of TIME_ZONES) {
  setTimeZone(timeZone)
  const instants = [
    ...LOCAL_INSTANTS.map(([y, mo, d, h, mi, s, ms]) =>
      new Date(y, mo - 1, d, h, mi, s, ms).getTime()
    ),
    ...RANDOM_INSTANTS,
  ]

  for (const [name, schedule] of Object.entries(SCHEDULES)) {
    for (const ms of instants) {
      const now = dayjs(ms)
      const settings = {
        ...schedule,
        startHour: parseTimeInputValue(schedule.startHour, null),
        endHour: parseTimeInputValue(schedule.endHour, null),
      }
      const window = getWorkingWindow(now, settings)
      const result = calculateEarnings(now, settings)
      const pair = ({ earned, total }: { earned: number; total: number }) => [
        earned,
        total,
      ]

      earnings.push({
        timeZone,
        schedule: name,
        now: ms,
        window: [window.start.valueOf(), window.end.valueOf()],
        scheduled: isScheduledDay(now, schedule.workingDays),
        hour: pair(result.hour),
        day: pair(result.day),
        week: pair(result.week),
        month: pair(result.month),
        year: pair(result.year),
        rates: [
          result.rates.perSecond,
          result.rates.perMinute,
          result.rates.perHour,
          result.rates.perDay,
        ],
        nextPayday: [
          result.nextPayday.date.getTime(),
          result.nextPayday.daysLeft,
          result.nextPayday.isToday,
          result.nextPayday.amount,
        ],
      })
    }
  }
}

// Paydays don't depend on the zone: the day of month for each payday 1-31
setTimeZone('Europe/Kyiv')
const paydays = [
  ...Array.from({ length: 12 }, (_, index) => [2026, index + 1]),
  [2028, 2],
].map(([year, month]) => ({
  year,
  month,
  days: Array.from({ length: 31 }, (_, index) =>
    getPaydayInMonth(dayjs(new Date(year, month - 1, 10)), index + 1).date()
  ),
}))

const CURRENCIES = ['UAH', 'USD', 'EUR', 'PLN', 'CZK', 'RON', 'GBP', 'JPY']
const AMOUNTS = [
  0, 0.004, 0.005, 0.00049999, 0.0125, 0.125, 0.12345, 1.005, 2.675, 7.5,
  999.995, 1234.5, 54321, 1234567.891, 123456789.98765, 1e9,
]
const currency = CURRENCIES.flatMap((code) =>
  AMOUNTS.flatMap((amount) =>
    [2, 4].map((digits) => ({
      amount,
      currency: code,
      digits,
      text: formatCurrency(amount, code, digits),
    }))
  )
)

const currencyParts = CURRENCIES.flatMap((code) =>
  AMOUNTS.flatMap((amount) =>
    [2, 4].map((digits) => ({
      amount,
      currency: code,
      digits,
      parts: formatCurrencyParts(amount, code, digits),
    }))
  )
)

// The settings pane's coupled fields (settingsDraft.ts): each edit applied
// to a few schedules, with times anchored to a day without a DST change, as
// the pane anchors them to today
setTimeZone('Europe/Kyiv')
const DRAFT_DAY = new Date(2026, 9, 29)
const DRAFT_SCHEDULES: [string, string, number][] = [
  ['09:00', '17:00', 8],
  ['09:00', '17:20', 8.33],
  ['22:00', '06:00', 8],
  ['10:00', '', 7.5],
  ['', '', 8],
  ['09:00', '09:00', 8],
]
type DraftEdit = [string, string | number]
const DRAFT_EDITS: DraftEdit[] = [
  ...['08:30', '16:00', '23:30', '00:00', '09:00'].map(
    (time): DraftEdit => ['startHour', time]
  ),
  ...['18:00', '08:00', '09:00', '17:19', '23:59', '00:00'].map(
    (time): DraftEdit => ['endHour', time]
  ),
  ...[1, 8, 8.33, 8.05, 12, 24, 0, -3, 30].map(
    (hours): DraftEdit => ['workingHoursPerDay', hours]
  ),
  ...[21, 0, 40, 21.5].map((days): DraftEdit => ['workingDays', days]),
  ...[15, 0, 31.9, 40].map((day): DraftEdit => ['payday', day]),
]
const drafts = DRAFT_SCHEDULES.flatMap(([startHour, endHour, workingHoursPerDay]) =>
  DRAFT_EDITS.map(([field, value]) => {
    const values: SettingsValues = {
      monthlySalary: 1000,
      monthlySalaryCurrency: 'UAH',
      earningsCurrency: 'UAH',
      workingHoursPerDay,
      workingDays: 22,
      payday: 1,
      startHour: parseTimeInputValue(startHour, DRAFT_DAY),
      endHour: parseTimeInputValue(endHour, DRAFT_DAY),
    }
    const time = () => parseTimeInputValue(value as string, DRAFT_DAY)
    const next =
      field === 'startHour'
        ? withStartHour(values, time())
        : field === 'endHour'
          ? withEndHour(values, time())
          : field === 'workingHoursPerDay'
            ? withWorkingHoursPerDay(values, String(value))
            : field === 'workingDays'
              ? withWorkingDays(values, String(value))
              : withPayday(values, String(value))

    return {
      before: { startHour, endHour, workingHoursPerDay },
      field,
      value,
      after: {
        startHour: formatTimeInputValue(next.startHour),
        endHour: formatTimeInputValue(next.endHour),
        workingHoursPerDay: next.workingHoursPerDay,
        workingDays: next.workingDays,
        payday: next.payday,
      },
    }
  })
)

// getScheduledNotifications: the end of yesterday's and today's working
// windows and payday at the start time, for a few settings and instants
const NOTIFICATION_SETTINGS: Record<string, Record<string, unknown>> = {
  office: { monthlySalary: 54321, payday: 29 },
  overnight: { monthlySalary: 54321, startHour: '22:00', endHour: '06:00', payday: 30 },
  noEnd: { monthlySalary: 54321, startHour: '10:00', endHour: '', workingHoursPerDay: 7.5, payday: 2 },
  lastDayPayday: { monthlySalary: 54321, payday: 31 },
  fewDays: { monthlySalary: 54321, workingDays: 3, payday: 1 },
  endOfDayOnly: { monthlySalary: 54321, payday: 29, notifyPayday: false },
  paydayOnly: { monthlySalary: 54321, payday: 29, notifyEndOfDay: false },
  unpaid: { monthlySalary: 0, payday: 29 },
}
const NOTIFICATION_INSTANTS: number[][] = [
  [2026, 10, 29, 8, 0, 0, 0],
  [2026, 10, 29, 17, 0, 0, 0],
  [2026, 10, 29, 23, 30, 0, 0],
  [2026, 10, 30, 3, 0, 0, 0],
  [2026, 10, 31, 7, 0, 0, 0],
  [2026, 11, 2, 9, 0, 0, 0],
  [2026, 11, 3, 12, 0, 0, 0],
  [2026, 11, 30, 12, 0, 0, 0],
  [2026, 2, 28, 10, 0, 0, 0],
  [2026, 3, 30, 1, 0, 0, 0],
  [2026, 12, 31, 18, 0, 0, 0],
]
const notifications = ['Europe/Kyiv', 'America/New_York'].flatMap((timeZone) => {
  setTimeZone(timeZone)

  return Object.entries(NOTIFICATION_SETTINGS).flatMap(([name, raw]) =>
    NOTIFICATION_INSTANTS.map(([y, mo, d, h, mi, s, ms]) => {
      const now = new Date(y, mo - 1, d, h, mi, s, ms).getTime()

      return {
        timeZone,
        settings: name,
        now,
        scheduled: getScheduledNotifications(dayjs(now), sanitizeSettings(raw)).map(
          ({ kind, key, at }) => ({ kind, key, at: at.valueOf() })
        ),
      }
    })
  )
})

// Inputs JSON can't hold go in as strings
const NORMALIZER_INPUTS: (number | string)[] = [
  -5, -0.5, 0, 0.25, 0.5, 1, 1.5, 7.9, 8, 15.7, 22, 23.99, 24, 24.5, 31, 31.5,
  40, 1e9, 'NaN', 'Infinity', '-Infinity',
]
const normalizers = NORMALIZER_INPUTS.map((input) => {
  const value = typeof input === 'string' ? Number(input) : input

  return {
    input,
    workingDays: normalizeWorkingDays(value),
    payday: normalizePayday(value),
    workingHoursPerDay: normalizeWorkingHoursPerDay(value),
  }
})

const TIME_INPUTS = [
  '09:00', '00:00', '23:59', '17:19', '7:30', '24:00', '25:99', '12:5', '',
  'ab:cd', '12:345', ' 09:00', '09:00 ',
]
const times = TIME_INPUTS.map((input) => ({
  input,
  // A fixed reference day keeps the result from depending on today
  output: formatTimeInputValue(parseTimeInputValue(input, new Date(2026, 9, 29))) || null,
}))

const VALID = {
  monthlySalary: 54321.5,
  monthlySalaryCurrency: 'EUR',
  earningsCurrency: 'PLN',
  workingHoursPerDay: 7.5,
  workingDays: 20,
  payday: 25,
  startHour: '08:30',
  endHour: '16:00',
  selectedPeriod: 'month',
  theme: 'dark',
  showInMenuBar: false,
  menuBarAmount: 'selected',
  launchAtLogin: true,
  notifyEndOfDay: false,
  notifyPayday: false,
}
const SETTINGS_INPUTS: unknown[] = [
  null,
  'settings',
  42,
  [],
  {},
  VALID,
  { ...VALID, unknownKey: 1 },
  { monthlySalary: -1, workingDays: 0, payday: 0, workingHoursPerDay: 0 },
  { monthlySalary: 2e9, workingDays: 40, payday: 99, workingHoursPerDay: 30 },
  { monthlySalary: '1000', workingDays: '22', payday: '5' },
  { monthlySalary: true, showInMenuBar: 1, launchAtLogin: 'true' },
  { workingDays: 0.5, payday: 15.7, workingHoursPerDay: 8.33 },
  { monthlySalaryCurrency: 'usd', earningsCurrency: 'USDT' },
  { monthlySalaryCurrency: 'U1D', earningsCurrency: '' },
  { startHour: '', endHour: '' },
  { startHour: '9:00', endHour: '24:00' },
  { startHour: '23:59', endHour: '00:00' },
  { startHour: '12:60', endHour: '09:00 ' },
  { selectedPeriod: 'decade', theme: 'auto', menuBarAmount: 'week' },
  { selectedPeriod: 'hour', theme: 'light', menuBarAmount: 'day' },
  { selectedPeriod: 'year', theme: 'system' },
  { notifyEndOfDay: null, notifyPayday: true },
]
const settings = SETTINGS_INPUTS.map((input) => ({
  input,
  output: sanitizeSettings(input),
}))

// One case per line keeps diffs of a regenerated fixture readable
const lines = (items: unknown[]) =>
  `[\n${items.map((item) => `    ${JSON.stringify(item)}`).join(',\n')}\n  ]`

writeFileSync(
  outputPath,
  `{
  "reference": ${JSON.stringify(reference)},
  "schedules": ${JSON.stringify(SCHEDULES)},
  "earnings": ${lines(earnings)},
  "paydays": ${lines(paydays)},
  "currency": ${lines(currency)},
  "currencyParts": ${lines(currencyParts)},
  "drafts": ${lines(drafts)},
  "notificationSettings": ${JSON.stringify(NOTIFICATION_SETTINGS)},
  "notifications": ${lines(notifications)},
  "normalizers": ${lines(normalizers)},
  "times": ${lines(times)},
  "settings": ${lines(settings)}
}
`
)

console.log(
  `${earnings.length} earnings cases, ${currency.length} amounts → ${outputPath}`
)
