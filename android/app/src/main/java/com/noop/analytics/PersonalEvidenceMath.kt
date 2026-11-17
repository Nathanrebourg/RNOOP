package com.noop.analytics
internal object PersonalEvidenceMath {
 fun median(x:List<Double>):Double? {val s=x.sorted();if(s.isEmpty())return null;return if(s.size%2==0)(s[s.size/2-1]+s[s.size/2])/2 else s[s.size/2]}
 fun same(a:Double?,b:Double?):Boolean = if(a==null||b==null) a==null&&b==null else a.toDouble()==b.toDouble()
 fun ascii(s:String)=s.isNotEmpty() && s.length<=200 && s.all{it.code in 32..126}
}
