#import "FBTTextSearch.h"

NSArray<NSString *> *FBTSearchTokens(NSString *query) {
    NSString *normalized = query.lowercaseString ?: @"";
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *token in [normalized componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (token.length) [tokens addObject:token];
    }
    return tokens.copy;
}

BOOL FBTSearchHaystackMatchesTokens(NSString *haystack, NSArray<NSString *> *tokens) {
    NSString *normalized = haystack.lowercaseString ?: @"";
    for (NSString *token in tokens) {
        if ([normalized rangeOfString:token].location == NSNotFound) return NO;
    }
    return YES;
}

BOOL FBTSearchQueryMatchesHaystack(NSString *query, NSString *haystack) {
    return FBTSearchHaystackMatchesTokens(haystack, FBTSearchTokens(query));
}
