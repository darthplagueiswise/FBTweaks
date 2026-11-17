#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSArray<NSString *> *FBTSearchTokens(NSString *_Nullable query);
BOOL FBTSearchHaystackMatchesTokens(NSString *_Nullable haystack, NSArray<NSString *> *tokens);
BOOL FBTSearchQueryMatchesHaystack(NSString *_Nullable query, NSString *_Nullable haystack);

NS_ASSUME_NONNULL_END
