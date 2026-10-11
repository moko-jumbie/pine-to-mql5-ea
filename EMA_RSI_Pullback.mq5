//+------------------------------------------------------------------+
//|                                          EMA_RSI_Pullback.mq5    |
//|            Pine Script -> MQL5 conversion demo (educational)     |
//|   Faithful port of ema-rsi-pullback.pine: same logic, same       |
//|   parameters, same ATR-based risk model.                         |
//|   NOTE: written carefully but not compiled in MetaEditor here —   |
//|   press F7 in MetaEditor and fix any warnings before live use.   |
//|   Educational use only. Not financial advice.                    |
//+------------------------------------------------------------------+
#property copyright "Pine->MQL5 conversion demo"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

//--- Inputs  (Pine input.* equivalents)
input int    InpEmaFast   = 50;         // Fast EMA Length
input int    InpEmaSlow   = 200;        // Slow EMA Length
input int    InpRsiPeriod = 14;         // RSI Length
input int    InpRsiLevel  = 40;         // RSI Pullback Level
input int    InpAtrPeriod = 14;         // ATR Length
input double InpAtrStop   = 2.0;        // ATR Stop Multiplier
input double InpAtrTake   = 3.0;        // ATR Target Multiplier
input double InpLots      = 0.10;       // Position Size (lots)
input ulong  InpMagic     = 20261011;   // EA Magic Number

//--- Indicator handles (Pine calls ta.* once per bar; here we create
//--- handles once and read their buffers — the MQL5 way)
int      hEmaFast = INVALID_HANDLE;
int      hEmaSlow = INVALID_HANDLE;
int      hRsi     = INVALID_HANDLE;
int      hAtr     = INVALID_HANDLE;
datetime lastBar  = 0;

//+------------------------------------------------------------------+
//| OnInit: create indicator handles (like Pine's first-bar setup)   |
//+------------------------------------------------------------------+
int OnInit()
{
   hEmaFast = iMA(_Symbol, PERIOD_CURRENT, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hEmaSlow = iMA(_Symbol, PERIOD_CURRENT, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   hRsi     = iRSI(_Symbol, PERIOD_CURRENT, InpRsiPeriod, PRICE_CLOSE);
   hAtr     = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);

   if(hEmaFast == INVALID_HANDLE || hEmaSlow == INVALID_HANDLE ||
      hRsi == INVALID_HANDLE     || hAtr == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit: release handles                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hEmaFast);
   IndicatorRelease(hEmaSlow);
   IndicatorRelease(hRsi);
   IndicatorRelease(hAtr);
}

//+------------------------------------------------------------------+
//| New-bar detector (Pine evaluates on bar close; we do the same)    |
//+------------------------------------------------------------------+
bool NewBar()
{
   datetime t[1];
   if(CopyTime(_Symbol, PERIOD_CURRENT, 0, 1, t) < 1)
      return false;
   if(t[0] != lastBar)
   {
      lastBar = t[0];
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| One position at a time, identified by our magic number            |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == (long)InpMagic)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| OnTick: the strategy itself                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!NewBar())
      return;

   // CopyBuffer fills oldest-first by default, so with start_pos=1,
   // count=3: index 2 = last closed bar, index 1 = the bar before it.
   // (Pine series are newest-last: close[1] == our cls[2].)
   double emaF[], emaS[], rsi[], atr[], cls[];
   if(CopyBuffer(hEmaFast, 0, 1, 3, emaF) < 3) return;
   if(CopyBuffer(hEmaSlow, 0, 1, 3, emaS) < 3) return;
   if(CopyBuffer(hRsi,     0, 1, 3, rsi)  < 3) return;
   if(CopyBuffer(hAtr,     0, 1, 3, atr)  < 3) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 1, 3, cls) < 3) return;

   double c1   = cls[2];
   double f1   = emaF[2];
   double s1   = emaS[2];
   double rsi1 = rsi[2];   // RSI on last closed bar  (Pine: rsiVal)
   double rsi2 = rsi[1];   // RSI one bar earlier     (Pine: rsiVal[1])
   double atr1 = atr[2];

   //--- Trend filter: close > EMA50 > EMA200 (Pine: inUptrend)
   bool uptrend   = (c1 > f1) && (f1 > s1);
   bool downtrend = (c1 < f1) && (f1 < s1);

   //--- Triggers: RSI crossing under 40 in an uptrend, over 60 in a downtrend
   //--- (Pine: ta.crossunder(rsiVal, rsiLevel) / ta.crossover(rsiVal, 100-rsiLevel))
   bool longTrigger  =  uptrend   && (rsi1 <  InpRsiLevel)       && (rsi2 >=  InpRsiLevel);
   bool shortTrigger =  downtrend && (rsi1 > (100 - InpRsiLevel)) && (rsi2 <= (100 - InpRsiLevel));

   if(HasOpenPosition())
      return;

   //--- ATR-based risk, prices normalized to the symbol's digits
   //--- (Pine: strategy.exit with stop= / limit=)
   if(longTrigger)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(ask - InpAtrStop * atr1, _Digits);
      double tp  = NormalizeDouble(ask + InpAtrTake * atr1, _Digits);
      if(!trade.Buy(InpLots, _Symbol, 0.0, sl, tp, "EMA/RSI pullback long"))
         Print("Buy failed: ", trade.ResultRetcodeDescription());
   }
   else if(shortTrigger)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(bid + InpAtrStop * atr1, _Digits);
      double tp  = NormalizeDouble(bid - InpAtrTake * atr1, _Digits);
      if(!trade.Sell(InpLots, _Symbol, 0.0, sl, tp, "EMA/RSI pullback short"))
         Print("Sell failed: ", trade.ResultRetcodeDescription());
   }
}
//+------------------------------------------------------------------+
