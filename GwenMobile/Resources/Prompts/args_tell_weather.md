place=The place whose weather is asked, in the user's words; empty for here.
day=Only the fallback when no day is named at all; tomorrow when no day is named.
dayOffset=Whole days from today for a relative day: 0 today, 1 tomorrow, 2 the day after tomorrow, 3 the day after the day after tomorrow, 4 in four days. Fill it next to date for every relative day; both must name the same day.
date=Absolute YYYY-MM-DD computed from the current date for every named day, relative or fixed (a weekday, "12 October", "tomorrow"); it wins over dayOffset and day.
