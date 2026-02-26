//+------------------------------------------------------------------+
//|                                   BFA_VOLATILITY_MONITOR.mq5    |
//|                         Volatility Index Real-time WebSocket     |
//+------------------------------------------------------------------+
#property copyright "BFA VOLATILITY MONITOR"
#property version   "1.00"
#property strict

//--- Input Parameters
input group "=== WEBSOCKET SETTINGS ==="
input string InpWebSocketUrl = "wss://bfa-volatility-index-monitor.onrender.com"; // WebSocket Server URL
input bool InpInstantRemoval = true; // Instantly remove signals when conditions not met
input int InpHeartbeatInterval = 30; // Heartbeat interval (seconds)
input int InpReconnectAttempts = 3; // Max reconnection attempts

input group "=== SIGNAL LOGIC SETTINGS ==="
input int InpBBPeriod = 20;
input double InpBBDeviation = 2.0;
input int InpSMAPeriod = 10;
input int InpEMAPeriod = 10;
input int InpSlopeBars = 5;
input double InpMinSlopeThreshold = 0.0;
input int InpATRPeriod = 14;        // ATR period for volatility classification
input double InpHighVolThreshold = 0.5;  // ATR% above this = High
input double InpLowVolThreshold  = 0.2;  // ATR% below this = Low

input group "=== INDICATOR COLORS ==="
input color InpBBColor = clrGold;
input color InpSMAColor = clrOrangeRed;
input color InpEMAColor = clrDeepSkyBlue;
input int InpBBWidth = 1;
input int InpSMAWidth = 2;
input int InpEMAWidth = 2;

input group "=== SYMBOL MONITORING ==="
input bool InpMonitorVol5     = true;
input bool InpMonitorVol10    = true;
input bool InpMonitorVol15    = true;
input bool InpMonitorVol25    = true;
input bool InpMonitorVol30    = true;
input bool InpMonitorVol50    = true;
input bool InpMonitorVol75    = true;
input bool InpMonitorVol90    = true;
input bool InpMonitorVol100   = true;
input bool InpMonitorVol5_1s  = true;
input bool InpMonitorVol10_1s = true;
input bool InpMonitorVol15_1s = true;
input bool InpMonitorVol25_1s = true;
input bool InpMonitorVol30_1s = true;
input bool InpMonitorVol50_1s = true;
input bool InpMonitorVol75_1s = true;
input bool InpMonitorVol90_1s = true;
input bool InpMonitorVol100_1s= true;
input bool InpMonitorVol150_1s= true;
input bool InpMonitorVol250_1s= true;

input group "=== DEBUG SETTINGS ==="
input bool InpEnableDebugLog = false;

//--- Structs
struct ActiveSignal
{
   string symbol;
   string timeframe;
   string tradeType;
   string h4Trend;
   string d1Trend;
   double minLot;
   double minMargin;
   double minSpread;
   string volLevel;
   int    priority;
   datetime timestamp;
   bool   active;
};

struct SymbolData
{
   string name;
   bool   enabled;
   bool   wasValidM30;
   bool   wasValidH1;
   bool   isValidM30;
   bool   isValidH1;
   int    hBB_M30;
   int    hSMA_M30;
   int    hEMA_M30;
   int    hBB_H1;
   int    hSMA_H1;
   int    hEMA_H1;
};

SymbolData  symbols[];
ActiveSignal activeSignals[];
int totalSymbols = 20;

int handleBB, handleSMA, handleEMA;

datetime lastHeartbeat = 0;
datetime lastSuccessfulRequest = 0;
bool isConnected = false;
int consecutiveFailures = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   ArrayResize(symbols, totalSymbols);
   ArrayResize(activeSignals, 0);

   symbols[0].name  = "Volatility 5 Index";    symbols[0].enabled  = InpMonitorVol5;
   symbols[1].name  = "Volatility 10 Index";   symbols[1].enabled  = InpMonitorVol10;
   symbols[2].name  = "Volatility 15 Index";   symbols[2].enabled  = InpMonitorVol15;
   symbols[3].name  = "Volatility 25 Index";   symbols[3].enabled  = InpMonitorVol25;
   symbols[4].name  = "Volatility 30 Index";   symbols[4].enabled  = InpMonitorVol30;
   symbols[5].name  = "Volatility 50 Index";   symbols[5].enabled  = InpMonitorVol50;
   symbols[6].name  = "Volatility 75 Index";   symbols[6].enabled  = InpMonitorVol75;
   symbols[7].name  = "Volatility 90 Index";   symbols[7].enabled  = InpMonitorVol90;
   symbols[8].name  = "Volatility 100 Index";  symbols[8].enabled  = InpMonitorVol100;
   symbols[9].name  = "Volatility 5 (1s) Index";   symbols[9].enabled  = InpMonitorVol5_1s;
   symbols[10].name = "Volatility 10 (1s) Index";  symbols[10].enabled = InpMonitorVol10_1s;
   symbols[11].name = "Volatility 15 (1s) Index";  symbols[11].enabled = InpMonitorVol15_1s;
   symbols[12].name = "Volatility 25 (1s) Index";  symbols[12].enabled = InpMonitorVol25_1s;
   symbols[13].name = "Volatility 30 (1s) Index";  symbols[13].enabled = InpMonitorVol30_1s;
   symbols[14].name = "Volatility 50 (1s) Index";  symbols[14].enabled = InpMonitorVol50_1s;
   symbols[15].name = "Volatility 75 (1s) Index";  symbols[15].enabled = InpMonitorVol75_1s;
   symbols[16].name = "Volatility 90 (1s) Index";  symbols[16].enabled = InpMonitorVol90_1s;
   symbols[17].name = "Volatility 100 (1s) Index"; symbols[17].enabled = InpMonitorVol100_1s;
   symbols[18].name = "Volatility 150 (1s) Index"; symbols[18].enabled = InpMonitorVol150_1s;
   symbols[19].name = "Volatility 250 (1s) Index"; symbols[19].enabled = InpMonitorVol250_1s;

   Print("🔧 Creating indicator handles for Volatility symbols...");
   int successCount = 0;

   for(int i = 0; i < totalSymbols; i++)
   {
      symbols[i].wasValidM30 = false;
      symbols[i].wasValidH1  = false;
      symbols[i].isValidM30  = false;
      symbols[i].isValidH1   = false;

      if(!symbols[i].enabled)
      {
         symbols[i].hBB_M30 = INVALID_HANDLE;
         symbols[i].hSMA_M30= INVALID_HANDLE;
         symbols[i].hEMA_M30= INVALID_HANDLE;
         symbols[i].hBB_H1  = INVALID_HANDLE;
         symbols[i].hSMA_H1 = INVALID_HANDLE;
         symbols[i].hEMA_H1 = INVALID_HANDLE;
         continue;
      }

      if(!SymbolSelect(symbols[i].name, true))
      {
         Print("⚠️ Failed to select symbol: ", symbols[i].name);
         symbols[i].enabled = false;
         continue;
      }

      symbols[i].hBB_M30  = iBands(symbols[i].name, PERIOD_M30, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
      symbols[i].hSMA_M30 = iMA(symbols[i].name, PERIOD_M30, InpSMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
      symbols[i].hEMA_M30 = iMA(symbols[i].name, PERIOD_M30, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

      symbols[i].hBB_H1   = iBands(symbols[i].name, PERIOD_H1, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
      symbols[i].hSMA_H1  = iMA(symbols[i].name, PERIOD_H1, InpSMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
      symbols[i].hEMA_H1  = iMA(symbols[i].name, PERIOD_H1, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

      if(symbols[i].hBB_M30 == INVALID_HANDLE || symbols[i].hSMA_M30 == INVALID_HANDLE ||
         symbols[i].hEMA_M30 == INVALID_HANDLE || symbols[i].hBB_H1   == INVALID_HANDLE ||
         symbols[i].hSMA_H1  == INVALID_HANDLE || symbols[i].hEMA_H1  == INVALID_HANDLE)
      {
         Print("❌ Failed to create indicators for ", symbols[i].name);
         symbols[i].enabled = false;
         continue;
      }

      successCount++;
      Print("✅ ", symbols[i].name, " - handles created");
   }

   Print("✅ Successfully created handles for ", successCount, " volatility symbols");

   handleBB  = iBands(_Symbol, PERIOD_CURRENT, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   handleSMA = iMA(_Symbol, PERIOD_CURRENT, InpSMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   handleEMA = iMA(_Symbol, PERIOD_CURRENT, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(handleBB == INVALID_HANDLE || handleSMA == INVALID_HANDLE || handleEMA == INVALID_HANDLE)
   {
      Print("❌ Error creating chart indicators!");
      return(INIT_FAILED);
   }

   ChartIndicatorAdd(0, 0, handleBB);
   ChartIndicatorAdd(0, 0, handleSMA);
   ChartIndicatorAdd(0, 0, handleEMA);

   CreateIndicatorLines();

   Print("╔════════════════════════════════════════╗");
   Print("║  BFA VOLATILITY MONITOR v1.00          ║");
   Print("║  20 Volatility Indices Tracked         ║");
   Print("╚════════════════════════════════════════╝");
   Print("📡 WebSocket: ", InpWebSocketUrl);

   if(SendHeartbeat())
   {
      Print("✅ Connected to server!");
      isConnected = true;
   }
   else
   {
      Print("⚠️ Initial connection failed - will retry");
      isConnected = false;
   }

   Sleep(3000);

   Print("🔍 Performing initial signal scan...");
   int foundSignals = 0;
   for(int i = 0; i < totalSymbols; i++)
   {
      if(!symbols[i].enabled) continue;
      CheckAndUpdateSignal(i, false);
      if(symbols[i].isValidM30) foundSignals++;
      CheckAndUpdateSignal(i, true);
      if(symbols[i].isValidH1) foundSignals++;
   }
   Print("✅ Initial scan complete! Found ", foundSignals, " active signals.");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void CreateIndicatorLines()
{
   int bars = Bars(_Symbol, PERIOD_CURRENT);
   if(bars < 100) return;

   for(int i = 0; i < 100; i++)
   {
      ObjectDelete(0, "BB_Upper_" + IntegerToString(i));
      ObjectDelete(0, "BB_Middle_" + IntegerToString(i));
      ObjectDelete(0, "BB_Lower_" + IntegerToString(i));
      ObjectDelete(0, "SMA_" + IntegerToString(i));
      ObjectDelete(0, "EMA_" + IntegerToString(i));
   }

   if(BarsCalculated(handleBB) < 2 || BarsCalculated(handleSMA) < 2 || BarsCalculated(handleEMA) < 2)
      return;

   int visibleBars = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   if(visibleBars > 100) visibleBars = 100;

   DrawIndicatorValues(visibleBars);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void DrawIndicatorValues(int barsCount)
{
   double bbUpper[], bbMiddle[], bbLower[], sma[], ema[];
   ArraySetAsSeries(bbUpper,  true);
   ArraySetAsSeries(bbMiddle, true);
   ArraySetAsSeries(bbLower,  true);
   ArraySetAsSeries(sma,      true);
   ArraySetAsSeries(ema,      true);

   if(CopyBuffer(handleBB, 1, 0, barsCount, bbUpper)  <= 0) return;
   if(CopyBuffer(handleBB, 0, 0, barsCount, bbMiddle) <= 0) return;
   if(CopyBuffer(handleBB, 2, 0, barsCount, bbLower)  <= 0) return;
   if(CopyBuffer(handleSMA, 0, 0, barsCount, sma)     <= 0) return;
   if(CopyBuffer(handleEMA, 0, 0, barsCount, ema)     <= 0) return;

   datetime time[];
   ArraySetAsSeries(time, true);
   CopyTime(_Symbol, PERIOD_CURRENT, 0, barsCount, time);

   for(int i = 0; i < barsCount - 1; i++)
   {
      CreateTrendLine("BB_Upper_"  + IntegerToString(i), time[i+1], bbUpper[i+1],  time[i], bbUpper[i],  InpBBColor, InpBBWidth);
      CreateTrendLine("BB_Middle_" + IntegerToString(i), time[i+1], bbMiddle[i+1], time[i], bbMiddle[i], InpBBColor, InpBBWidth + 1);
      CreateTrendLine("BB_Lower_"  + IntegerToString(i), time[i+1], bbLower[i+1],  time[i], bbLower[i],  InpBBColor, InpBBWidth);
      CreateTrendLine("SMA_" + IntegerToString(i), time[i+1], sma[i+1], time[i], sma[i], InpSMAColor, InpSMAWidth);
      CreateTrendLine("EMA_" + IntegerToString(i), time[i+1], ema[i+1], time[i], ema[i], InpEMAColor, InpEMAWidth);
   }
}

//+------------------------------------------------------------------+
void CreateTrendLine(string name, datetime time1, double price1, datetime time2, double price2, color clr, int width)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TREND, 0, time1, price1, time2, price2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i = 0; i < totalSymbols; i++)
   {
      if(symbols[i].hBB_M30  != INVALID_HANDLE) IndicatorRelease(symbols[i].hBB_M30);
      if(symbols[i].hSMA_M30 != INVALID_HANDLE) IndicatorRelease(symbols[i].hSMA_M30);
      if(symbols[i].hEMA_M30 != INVALID_HANDLE) IndicatorRelease(symbols[i].hEMA_M30);
      if(symbols[i].hBB_H1   != INVALID_HANDLE) IndicatorRelease(symbols[i].hBB_H1);
      if(symbols[i].hSMA_H1  != INVALID_HANDLE) IndicatorRelease(symbols[i].hSMA_H1);
      if(symbols[i].hEMA_H1  != INVALID_HANDLE) IndicatorRelease(symbols[i].hEMA_H1);
   }

   for(int i = 0; i < 100; i++)
   {
      ObjectDelete(0, "BB_Upper_"  + IntegerToString(i));
      ObjectDelete(0, "BB_Middle_" + IntegerToString(i));
      ObjectDelete(0, "BB_Lower_"  + IntegerToString(i));
      ObjectDelete(0, "SMA_" + IntegerToString(i));
      ObjectDelete(0, "EMA_" + IntegerToString(i));
   }

   if(handleBB  != INVALID_HANDLE) IndicatorRelease(handleBB);
   if(handleSMA != INVALID_HANDLE) IndicatorRelease(handleSMA);
   if(handleEMA != INVALID_HANDLE) IndicatorRelease(handleEMA);

   ChartRedraw(0);
   Print("BFA Volatility Monitor stopped - all handles released");
}

//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastUpdate  = 0;
   static datetime lastBarTime = 0;
   datetime currentTime = TimeCurrent();

   CheckConnectionHealth();

   datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
   bool newBar = (currentBarTime != lastBarTime);
   if(newBar)
   {
      lastBarTime = currentBarTime;
      if(InpEnableDebugLog)
         Print("📊 New M1 bar - scanning volatility symbols...");
   }

   for(int i = 0; i < totalSymbols; i++)
   {
      if(!symbols[i].enabled) continue;
      CheckAndUpdateSignal(i, false);
      CheckAndUpdateSignal(i, true);
   }

   if(currentTime - lastUpdate > 60)
   {
      int visibleBars = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
      if(visibleBars > 100) visibleBars = 100;
      DrawIndicatorValues(visibleBars);
      lastUpdate = currentTime;
   }
}

//+------------------------------------------------------------------+
void CheckConnectionHealth()
{
   datetime currentTime = TimeCurrent();
   if(currentTime - lastHeartbeat >= InpHeartbeatInterval)
   {
      bool success = SendHeartbeat();
      if(success)
      {
         if(!isConnected)
         {
            Print("✅ Reconnected to server!");
            isConnected = true;
            consecutiveFailures = 0;
            ResyncAllSignals();
         }
      }
      else
      {
         consecutiveFailures++;
         if(isConnected) Print("⚠️ Connection issue (attempt ", consecutiveFailures, ")");
         if(consecutiveFailures >= InpReconnectAttempts && isConnected)
         {
            Print("❌ Connection lost after ", consecutiveFailures, " failures");
            isConnected = false;
         }
      }
      lastHeartbeat = currentTime;
   }
}

//+------------------------------------------------------------------+
bool SendHeartbeat()
{
   string json = "{\"type\":\"heartbeat\",\"source\":\"volatility_monitor\",\"timestamp\":" +
                 IntegerToString((int)TimeCurrent()) +
                 ",\"active_signals\":" + IntegerToString(ArraySize(activeSignals)) + "}";
   return SendToWebSocket(json);
}

//+------------------------------------------------------------------+
void ResyncAllSignals()
{
   Print("🔄 Resyncing ", ArraySize(activeSignals), " active signals...");
   int successCount = 0;
   for(int i = 0; i < ArraySize(activeSignals); i++)
   {
      if(!activeSignals[i].active) continue;
      string json = BuildSignalJSON(activeSignals[i].symbol, activeSignals[i].timeframe,
                                    activeSignals[i].tradeType, activeSignals[i].h4Trend,
                                    activeSignals[i].d1Trend, activeSignals[i].minLot,
                                    activeSignals[i].minMargin, activeSignals[i].minSpread,
                                    activeSignals[i].volLevel, activeSignals[i].priority,
                                    activeSignals[i].timestamp);
      if(SendToWebSocket(json)) successCount++;
      Sleep(100);
   }
   Print("✅ Resynced ", successCount, "/", ArraySize(activeSignals), " signals");
}

//+------------------------------------------------------------------+
string BuildSignalJSON(string symbol, string tf, string tradeType, string h4Trend, string d1Trend,
                       double minLot, double minMargin, double minSpread, string volLevel, int priority, datetime ts)
{
   int lotDigits = 2;
   if(minLot < 0.01)  lotDigits = 3;
   if(minLot < 0.001) lotDigits = 4;

   return "{\"type\":\"signal\"," +
          "\"symbol\":\"" + symbol + "\"," +
          "\"timeframe\":\"" + tf + "\"," +
          "\"trade_type\":\"" + tradeType + "\"," +
          "\"h4_trend\":\"" + h4Trend + "\"," +
          "\"d1_trend\":\"" + d1Trend + "\"," +
          "\"min_lot\":" + DoubleToString(minLot, lotDigits) + "," +
          "\"min_margin\":" + DoubleToString(minMargin, 2) + "," +
          "\"min_spread\":" + DoubleToString(minSpread, 4) + "," +
          "\"vol_level\":\"" + volLevel + "\"," +
          "\"priority\":" + IntegerToString(priority) + "," +
          "\"timestamp\":" + IntegerToString((int)ts) + "}";
}

//+------------------------------------------------------------------+
double CalculateBBSlope(double &bbMiddle[], int bars)
{
   if(bars < 2) return 0;
   double totalChange = 0;
   int validChanges = 0;
   for(int i = 0; i < bars - 1; i++)
   {
      if(bbMiddle[i] != EMPTY_VALUE && bbMiddle[i + 1] != EMPTY_VALUE &&
         bbMiddle[i] != 0 && bbMiddle[i + 1] != 0)
      {
         totalChange += bbMiddle[i] - bbMiddle[i + 1];
         validChanges++;
      }
   }
   if(validChanges == 0) return 0;
   return totalChange / validChanges;
}

//+------------------------------------------------------------------+
void CheckAndUpdateSignal(int symbolIndex, bool isH1)
{
   if(!symbols[symbolIndex].enabled) return;

   string symbolName = symbols[symbolIndex].name;
   ENUM_TIMEFRAMES timeframe = isH1 ? PERIOD_H1 : PERIOD_M30;

   int hBB  = isH1 ? symbols[symbolIndex].hBB_H1  : symbols[symbolIndex].hBB_M30;
   int hSMA = isH1 ? symbols[symbolIndex].hSMA_H1 : symbols[symbolIndex].hSMA_M30;
   int hEMA = isH1 ? symbols[symbolIndex].hEMA_H1 : symbols[symbolIndex].hEMA_M30;

   if(hBB == INVALID_HANDLE || hSMA == INVALID_HANDLE || hEMA == INVALID_HANDLE) return;

   int barsNeeded = MathMax(InpSlopeBars + 2, 5);
   if(Bars(symbolName, timeframe) < barsNeeded) return;
   if(BarsCalculated(hBB)  < barsNeeded ||
      BarsCalculated(hSMA) < barsNeeded ||
      BarsCalculated(hEMA) < barsNeeded) return;

   double bbMiddle[], smaValues[], emaValues[];
   ArraySetAsSeries(bbMiddle,  true);
   ArraySetAsSeries(smaValues, true);
   ArraySetAsSeries(emaValues, true);

   if(CopyBuffer(hBB, 0, 0, barsNeeded, bbMiddle)  != barsNeeded) return;
   if(CopyBuffer(hSMA, 0, 0, barsNeeded, smaValues) != barsNeeded) return;
   if(CopyBuffer(hEMA, 0, 0, barsNeeded, emaValues) != barsNeeded) return;

   for(int i = 0; i < MathMin(3, barsNeeded); i++)
   {
      if(bbMiddle[i]  == EMPTY_VALUE || bbMiddle[i]  == 0 ||
         smaValues[i] == EMPTY_VALUE || smaValues[i] == 0 ||
         emaValues[i] == EMPTY_VALUE || emaValues[i] == 0) return;
   }

   double bbSlope  = CalculateBBSlope(bbMiddle, InpSlopeBars);
   double absSlope = MathAbs(bbSlope);

   bool   conditionsMet = false;
   string tradeType     = "";

   bool slopeOk = (absSlope >= InpMinSlopeThreshold);

   if(bbSlope > 0 && slopeOk && emaValues[0] > bbMiddle[0] && emaValues[0] > smaValues[0])
   {
      conditionsMet = true;
      tradeType = "BUY";
   }
   else if(bbSlope < 0 && slopeOk && emaValues[0] < bbMiddle[0] && emaValues[0] < smaValues[0])
   {
      conditionsMet = true;
      tradeType = "SELL";
   }

   if(InpEnableDebugLog)
   {
      string tf = EnumToString(timeframe);
      StringReplace(tf, "PERIOD_", "");
      Print("🔍 ", symbolName, " ", tf,
            " Slope:", DoubleToString(bbSlope, 6),
            " EMA:", DoubleToString(emaValues[0], 4),
            " BB:", DoubleToString(bbMiddle[0], 4),
            " SMA:", DoubleToString(smaValues[0], 4),
            " -> ", (conditionsMet ? tradeType : "NO SIGNAL"));
   }

   bool wasValid = isH1 ? symbols[symbolIndex].wasValidH1 : symbols[symbolIndex].wasValidM30;

   if(conditionsMet && !wasValid)
   {
      string h4Trend  = AnalyzeTrend(symbolName, PERIOD_H4);
      string d1Trend  = AnalyzeTrend(symbolName, PERIOD_D1);
      string volLevel  = GetATRVolatility(symbolName);
      double minLot    = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MIN);
      double minMargin = CalculateMargin(symbolName, minLot);
      double minSpread = CalculateSpreadCost(symbolName, minLot);

      AddActiveSignal(symbolName, timeframe, tradeType, h4Trend, d1Trend, minLot, minMargin, minSpread, volLevel);
      SendSignalToWebSocket(symbolName, timeframe, tradeType, h4Trend, d1Trend, minLot, minMargin, minSpread, volLevel);

      string tf = EnumToString(timeframe);
      StringReplace(tf, "PERIOD_", "");
      Print("✅ NEW SIGNAL: ", symbolName, " ", tf, " ", tradeType,
            " | Slope: ", DoubleToString(bbSlope, 6));
   }
   else if(!conditionsMet && wasValid && InpInstantRemoval)
   {
      RemoveActiveSignal(symbolName, timeframe);
      RemoveSignalFromWebSocket(symbolName, timeframe);

      string tf = EnumToString(timeframe);
      StringReplace(tf, "PERIOD_", "");
      Print("❌ REMOVED: ", symbolName, " ", tf, " (conditions no longer met)");
   }

   if(isH1)
   {
      symbols[symbolIndex].isValidH1  = conditionsMet;
      symbols[symbolIndex].wasValidH1 = conditionsMet;
   }
   else
   {
      symbols[symbolIndex].isValidM30  = conditionsMet;
      symbols[symbolIndex].wasValidM30 = conditionsMet;
   }
}

//+------------------------------------------------------------------+
string GetDisplaySymbol(string symbolName)
{
   string display = symbolName;
   StringReplace(display, " Index", "");
   return display;
}

//+------------------------------------------------------------------+
void AddActiveSignal(string symbolName, ENUM_TIMEFRAMES timeframe, string tradeType,
                     string h4Trend, string d1Trend, double minLot, double minMargin, double minSpread, string volLevel)
{
   string displaySymbol = GetDisplaySymbol(symbolName);
   string tf = EnumToString(timeframe);
   StringReplace(tf, "PERIOD_", "");

   for(int i = 0; i < ArraySize(activeSignals); i++)
   {
      if(activeSignals[i].symbol == displaySymbol && activeSignals[i].timeframe == tf)
      {
         activeSignals[i].tradeType = tradeType;
         activeSignals[i].h4Trend   = h4Trend;
         activeSignals[i].d1Trend   = d1Trend;
         activeSignals[i].minLot    = minLot;
         activeSignals[i].minMargin = minMargin;
         activeSignals[i].minSpread = minSpread;
         activeSignals[i].volLevel  = volLevel;
         activeSignals[i].timestamp = TimeCurrent();
         activeSignals[i].active    = true;
         return;
      }
   }

   int newSize = ArraySize(activeSignals) + 1;
   ArrayResize(activeSignals, newSize);
   activeSignals[newSize - 1].symbol    = displaySymbol;
   activeSignals[newSize - 1].timeframe = tf;
   activeSignals[newSize - 1].tradeType = tradeType;
   activeSignals[newSize - 1].h4Trend   = h4Trend;
   activeSignals[newSize - 1].d1Trend   = d1Trend;
   activeSignals[newSize - 1].minLot    = minLot;
   activeSignals[newSize - 1].minMargin = minMargin;
   activeSignals[newSize - 1].minSpread = minSpread;
   activeSignals[newSize - 1].volLevel  = volLevel;
   activeSignals[newSize - 1].priority  = (timeframe == PERIOD_H1) ? 2 : 1;
   activeSignals[newSize - 1].timestamp = TimeCurrent();
   activeSignals[newSize - 1].active    = true;
}

//+------------------------------------------------------------------+
void RemoveActiveSignal(string symbolName, ENUM_TIMEFRAMES timeframe)
{
   string displaySymbol = GetDisplaySymbol(symbolName);
   string tf = EnumToString(timeframe);
   StringReplace(tf, "PERIOD_", "");
   for(int i = 0; i < ArraySize(activeSignals); i++)
   {
      if(activeSignals[i].symbol == displaySymbol && activeSignals[i].timeframe == tf)
      {
         activeSignals[i].active = false;
         return;
      }
   }
}

//+------------------------------------------------------------------+
void SendSignalToWebSocket(string symbolName, ENUM_TIMEFRAMES timeframe, string tradeType,
                           string h4Trend, string d1Trend, double minLot, double minMargin, double minSpread, string volLevel)
{
   string displaySymbol = GetDisplaySymbol(symbolName);
   string tf = EnumToString(timeframe);
   StringReplace(tf, "PERIOD_", "");
   int priority = (timeframe == PERIOD_H1) ? 2 : 1;
   string json = BuildSignalJSON(displaySymbol, tf, tradeType, h4Trend, d1Trend,
                                 minLot, minMargin, minSpread, volLevel, priority, TimeCurrent());
   SendToWebSocket(json);
}

//+------------------------------------------------------------------+
void RemoveSignalFromWebSocket(string symbolName, ENUM_TIMEFRAMES timeframe)
{
   string displaySymbol = GetDisplaySymbol(symbolName);
   string tf = EnumToString(timeframe);
   StringReplace(tf, "PERIOD_", "");
   string json = "{\"type\":\"remove_signal\"," +
                 "\"action\":\"remove\"," +
                 "\"symbol\":\"" + displaySymbol + "\"," +
                 "\"timeframe\":\"" + tf + "\"}";
   if(InpEnableDebugLog) Print("📤 Sending removal: ", json);
   SendToWebSocket(json);
}

//+------------------------------------------------------------------+
bool SendToWebSocket(string json)
{
   string url = InpWebSocketUrl;
   StringReplace(url, "ws://",  "http://");
   StringReplace(url, "wss://", "https://");

   char post[], result[];
   int len = StringToCharArray(json, post, 0, WHOLE_ARRAY, CP_UTF8);
   if(len > 0) ArrayResize(post, len - 1);

   string headers = "Content-Type: application/json\r\n";
   ResetLastError();
   int res = WebRequest("POST", url, headers, 5000, post, result, headers);

   if(res == -1)
   {
      int error = GetLastError();
      if(error == 4060) Print("⚠️ WebRequest NOT enabled! Whitelist: ", url);
      else if(InpEnableDebugLog) Print("❌ WebRequest error: ", error);
      return false;
   }
   else if(res == 200)
   {
      lastSuccessfulRequest = TimeCurrent();
      if(InpEnableDebugLog)
      {
         string response = CharArrayToString(result);
         if(StringLen(response) > 0) Print("✅ Server: ", response);
      }
      return true;
   }
   else
   {
      if(InpEnableDebugLog) Print("⚠️ HTTP ", res);
      return false;
   }
}

//+------------------------------------------------------------------+
string AnalyzeTrend(string symbolName, ENUM_TIMEFRAMES timeframe)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbolName, timeframe, 0, InpBBPeriod + InpEMAPeriod + 5, rates);
   if(copied < InpBBPeriod + 5) return "No Data";

   double bbMiddle[];
   ArrayResize(bbMiddle, InpBBPeriod);
   ArraySetAsSeries(bbMiddle, true);
   for(int i = 0; i < 5; i++)
   {
      double sum = 0;
      for(int j = 0; j < InpBBPeriod; j++) sum += rates[i + j].close;
      bbMiddle[i] = sum / InpBBPeriod;
   }

   double emaValues[];
   ArrayResize(emaValues, copied);
   ArraySetAsSeries(emaValues, false);
   double multiplier = 2.0 / (InpEMAPeriod + 1);
   emaValues[0] = rates[copied - 1].close;
   for(int i = 1; i < copied; i++)
      emaValues[i] = (rates[copied - 1 - i].close * multiplier) + (emaValues[i - 1] * (1 - multiplier));
   ArraySetAsSeries(emaValues, true);

   double bbSlope    = bbMiddle[0] - bbMiddle[1];
   double emaDistance= 0;
   if(bbMiddle[0] != 0) emaDistance = ((emaValues[0] - bbMiddle[0]) / bbMiddle[0]) * 100;

   double absDistance = MathAbs(emaDistance);
   string strength = "";
   if(absDistance > 0.15)      strength = "Strong";
   else if(absDistance > 0.08) strength = "Moderate";
   else if(absDistance > 0.03) strength = "Weak";
   else                        strength = "Very Weak";

   if(bbSlope > 0)      return strength + " Uptrend";
   else if(bbSlope < 0) return strength + " Downtrend";
   else                 return "Sideways";
}


//+------------------------------------------------------------------+
// Classify symbol volatility using ATR% = (ATR14 / Price) * 100
// High: > InpHighVolThreshold%   Medium: between   Low: < InpLowVolThreshold%
//+------------------------------------------------------------------+
string GetATRVolatility(string symbolName)
{
   int hATR = iATR(symbolName, PERIOD_H1, InpATRPeriod);
   if(hATR == INVALID_HANDLE) return "Unknown";

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(hATR, 0, 0, 1, atrBuf) <= 0)
   {
      IndicatorRelease(hATR);
      return "Unknown";
   }

   double price = SymbolInfoDouble(symbolName, SYMBOL_BID);
   if(price <= 0)
   {
      IndicatorRelease(hATR);
      return "Unknown";
   }

   IndicatorRelease(hATR);

   double atrPct = (atrBuf[0] / price) * 100.0;

   if(atrPct >= InpHighVolThreshold) return "High";
   if(atrPct >= InpLowVolThreshold)  return "Medium";
   return "Low";
}

//+------------------------------------------------------------------+
// Spread cost in $ = (Ask - Bid) x ContractSize x MinLot
//+------------------------------------------------------------------+
double CalculateSpreadCost(string symbolName, double minLot)
{
   double ask = SymbolInfoDouble(symbolName, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbolName, SYMBOL_BID);
   if(ask <= 0 || bid <= 0) return 0;
   double spread       = ask - bid;
   double contractSize = SymbolInfoDouble(symbolName, SYMBOL_TRADE_CONTRACT_SIZE);
   return spread * contractSize * minLot;
}

//+------------------------------------------------------------------+
double CalculateMargin(string symbolName, double lotSize)
{
   double margin = 0;

   double freshMinLot = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MIN);
   if(freshMinLot <= 0) return 0;
   double useLot = freshMinLot;

   double ask = SymbolInfoDouble(symbolName, SYMBOL_ASK);
   if(ask == 0) ask = SymbolInfoDouble(symbolName, SYMBOL_BID);
   if(ask == 0) return 0;

   // Try BUY margin
   if(OrderCalcMargin(ORDER_TYPE_BUY, symbolName, useLot, ask, margin) && margin > 0)
      return margin;

   // Try SELL margin
   margin = 0;
   if(OrderCalcMargin(ORDER_TYPE_SELL, symbolName, useLot, ask, margin) && margin > 0)
      return margin;

   // Fallback: SYMBOL_MARGIN_INITIAL
   double initialMargin = SymbolInfoDouble(symbolName, SYMBOL_MARGIN_INITIAL);
   if(initialMargin > 0)
      return initialMargin * useLot;

   // Last resort: leverage-based
   double contractSize = SymbolInfoDouble(symbolName, SYMBOL_TRADE_CONTRACT_SIZE);
   long leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
   if(leverage == 0) leverage = 1;
   return (contractSize * useLot * ask) / (double)leverage;
}
//+------------------------------------------------------------------+
