import unittest
from spoken_readings import clock,date,count,minutes
class SpokenReadingsTests(unittest.TestCase):
    def testMinutePrecisionAndPeriod(self):
        self.assertEqual(clock('09:30'),'ごぜんくじはん')
        self.assertEqual(clock('13:00'),'ごごいちじ')
        self.assertEqual(clock('17:15'),'ごごごじじゅうごふん')
        self.assertEqual(clock('00:00'),'ごぜんれいじ')
        self.assertEqual(clock('12:00'),'しょうご')
    def testDatesAndCounters(self):
        self.assertEqual(date('2026-10-24'),'にせんにじゅうろくねんじゅうがつにじゅうよっか')
        self.assertEqual(date('2026-11-07'),'にせんにじゅうろくねんじゅういちがつなのか')
        self.assertEqual(count(41),'よんじゅういっけん')
        self.assertEqual(minutes(30),'さんじゅっぷん')
    def testInvalidValuesCannotBecomeInventedTimes(self):
        for value in ('朝ごろ','24:00','9:30','13:99'):
            with self.assertRaises(ValueError):clock(value)
        with self.assertRaises(ValueError):date('2026-02-30')
