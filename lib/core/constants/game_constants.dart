// Game-wide constants

const String appName = 'Football Manager Sim';

// Player stat ranges
const int minOvr = 40;
const int maxOvr = 99;

// Age constants
const int minPlayableAge = 18;
const int maxPlayableAge = 41; // GK can play slightly longer
const int youthAcademyMinAge = 9;
const int youthAcademyMaxAge = 17;
const int youthAcademyCapacity = 15;
const int youthAutoPromoteAge = 18;

// Peak age
const int peakAgeStart = 24;
const int peakAgeEnd = 29;

// Decline
const int outfieldDeclineStart = 30;
const int goalkeeperDeclineStart = 34;
const int averageRetireMin = 35;
const int averageRetireMax = 40;

// Match constants
const int matchMinutes = 90;
const int normalMatchSpeedSeconds = 30;
const int fastMatchSpeedSeconds = 15;
const int maxSubstitutions = 3;
const int substitutionPerHalf = 3;

// Development
const double youngPlayerGrowthRate = 0.15;
const double peakPlayerGrowthRate = 0.08;
const double oldPlayerGrowthRate = 0.03;
const double performanceThresholdHigh = 7.5;
const double performanceThresholdMid = 5.5;
const double hotStreakThreshold = 3;

// Finance
const double ffpWageRatioLimit = 0.70;
const double minTransferBudget = 1000000;

// Scouting
const int scoutingCostDetailed = 5000;
const int scoutingCostTopLevel = 25000;
const int scoutingDaysDetailed = 2;
const int scoutingDaysTopLevel = 5;

// Youth development
const double youthGrowthMultiplier = 0.10;
const double youthPotentialGapClosure = 0.10;

// Drama
const double dramaMin = 0.0;
const double dramaMax = 100.0;
const double dramaThresholdMinor = 20.0;
const double dramaThresholdModerate = 40.0;
const double dramaThresholdHigh = 60.0;
const double dramaThresholdCritical = 80.0;

// Drama event impacts
const double dramaTransferRequest = 15.0;
const double dramaRivalryMatch = 10.0;
const double dramaMediaCriticism = 8.0;
const double dramaPlayerDispute = 12.0;
const double dramaWinningStreak = 5.0;
const double dramaMilestone = 10.0;
const double dramaFFPIssue = 20.0;
const double dramaUnverifiedRumor = 5.0;
const double dramaVerifiedRumor = 12.0;