# WorkManager (pulled in transitively by google_mobile_ads) uses Room 2.2.5.
# Room creates its generated WorkDatabase_Impl by reflection, but R8 full mode
# strips the class's no-arg constructor. Without that constructor the app dies
# in androidx.startup.InitializationProvider before Flutter starts.
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
