//
// This header file is used to generate PCH.
// Execute
//  :ClangGenPCHFromFile %
// to generate PCH file stdafx.h.pch
//
#ifndef STDAFX_H
#define STDAFX_H
  #ifdef __cplusplus
    #include<algorithm>
    #include<list>
    #include<map>
    #include<set>
    #include<string>
    #include<utility>
    #include<vector>
    
    #if __cplusplus >= 201103L  // C++11
      #include<array>
      #include<regex>
      #include<tuple>
    #endif
  #endif
#endif // STDAFX_H
