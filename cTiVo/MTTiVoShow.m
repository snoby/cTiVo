//
//  MTTiVoShow.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/18/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//
// Class for handling individual TiVo Shows

#import "MTTiVoShow.h"
#import "MTProgramTableView.h"
#import "MTiTunes.h"
#import "MTTiVoManager.h"
#import "NSString+RFC3339Date.h"
#import "mp4v2.h"

@interface MTTiVoShow () {
	
	NSXMLParser *parser;
	NSMutableString *elementString;
	NSMutableArray *elementArray;
	NSArray *arrayHolder;
	NSDictionary *parseTermMapping;

}
@property (nonatomic, strong) NSArray *vActor,
										*vExecProducer,
										*vProgramGenre,
										*vSeriesGenre,
										*vGuestStar,
										*vDirector;


@end

@implementation MTTiVoShow

@synthesize seriesTitle		 = _seriesTitle,
			episodeTitle	 = _episodeTitle,
			imageString		 = _imageString,
			tempTiVoName     = _tempTiVoName;

__DDLOGHERE__

-(id)init
{
    self = [super init];
    if (self) {
        _showID = 0;
		_gotDetails = NO;
		elementString = nil;
		_vActor = nil;
		_vExecProducer = nil;
        _vDirector = nil;
        _vGuestStar = nil;
		self.inProgress = @(NO); //This is the default
		_season = 0;
		_episode = 0;
		_episodeNumber = @"";
        _isQueued = NO;
		_episodeTitle = @"";
		_seriesTitle = @"";
//		_originalAirDate = @"";
		_episodeYear = 0;
		
		self.protectedShow = @(NO); //This is the default
		parseTermMapping = @{@"description" : @"showDescription", @"time": @"showTime"};

    }
    return self;
}

#pragma mark - GetDetails from Tivo and parse
-(NSArray *)parseNames:(NSArray *)nameSet
{
	if (!nameSet || ![nameSet respondsToSelector:@selector(count)] || nameSet.count == 0 ) { //|| [nameSet[0] isKindOfClass:[NSString class]]) {
		return nameSet;
	}
	NSRegularExpression *nameParse = [NSRegularExpression regularExpressionWithPattern:@"([^|]*)\\|([^|]*)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSMutableArray *newNames = [NSMutableArray array];
	for (NSString *name in nameSet) {
		NSTextCheckingResult *match = [nameParse firstMatchInString:name options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, name.length)];
		NSString *lastName = [name substringWithRange:[match rangeAtIndex:1]];
		NSString *firstName = [name substringWithRange:[match rangeAtIndex:2]];
		[newNames addObject:@{kMTLastName : lastName, kMTFirstName : firstName}];
	}
	return [NSArray arrayWithArray:newNames];
}

-(NSString *)nameString:(NSDictionary *)nameDictionary
{
    return [NSString stringWithFormat:@"%@ %@",nameDictionary[kMTFirstName] ? nameDictionary[kMTFirstName] : @"" ,nameDictionary[kMTLastName] ? nameDictionary[kMTLastName] : @"" ];
}

-(void)setShowLengthString:(NSString *)showLengthString
{
	if (showLengthString != _showLengthString) {
		_showLengthString = showLengthString;
		_showLength = [_showLengthString longLongValue]/1000;
	}
}


-(void)getShowDetail
{
	if (_gotDetails) {
		return;
	}
	DDLogVerbose(@"getting Detail for %@ at %@",self, _detailURL);
	_gotDetails = YES;
	@autoreleasepool {
//	NSString *detailURLString = [NSString stringWithFormat:@"https://%@/TiVoVideoDetails?id=%d",_tiVo.tiVo.hostName,_showID];
//	NSLog(@"Show Detail URL %@",detailURLString);
		NSURLResponse *detailResponse = nil;
		NSURLRequest *detailRequest = [NSURLRequest requestWithURL:_detailURL];;
		NSData *xml = [NSURLConnection sendSynchronousRequest:detailRequest returningResponse:&detailResponse error:nil];
		DDLogVerbose(@"Got Details for %@: %@", self, [[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding	]);

		parser = [[NSXMLParser alloc] initWithData:xml];
		parser.delegate = self;
		[parser parse];
		if (!_gotDetails) {
			DDLogMajor(@"GetDetails Fail for %@",_showTitle);
			DDLogMajor(@"Returned XML is %@",	[[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding	]);
		} else {
			DDLogDetail(@"GetDetails parsing Finished");
		}
		//keep XML until we convert video for metadata
		self.detailXML = xml;
		NSNotification *notification = [NSNotification notificationWithName:kMTNotificationDetailsLoaded object:self];
    [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:notification waitUntilDone:NO];
	}
}


#pragma mark - Queue encoding/decoding methods for persistent queue, copy/paste, and drag/drop

- (void) encodeWithCoder:(NSCoder *)encoder {
	//necessary for cut/paste drag/drop. 
	DDLogVerbose(@"encoding %@",self);
	[encoder encodeObject:[NSNumber numberWithInteger: _showID] forKey: kMTQueueID];
	[encoder encodeObject:_showTitle forKey: kMTQueueTitle];
	[encoder encodeObject:self.tiVoName forKey: kMTQueueTivo];
}

-(BOOL) isEqual:(id)object {
	MTTiVoShow * show = (MTTiVoShow *) object;
	return [self.showTitle isEqual: show.showTitle] &&
			self. showID == show.showID &&
		   [self.tiVoName isEqual: show.tiVoName];
}


- (id)initWithCoder:(NSCoder *)decoder {
	//keep parallel with updateFromDecodedShow
	if ((self = [self init])) {
		//NSString *title = [decoder decodeObjectForKey:kTitleKey];
		//float rating = [decoder decodeFloatForKey:kRatingKey];
		self.showID   = [[decoder decodeObjectForKey: kMTQueueID] intValue];
		self.showTitle= [decoder decodeObjectForKey: kMTQueueTitle] ;
		NSString * tivoName = [decoder decodeObjectForKey: kMTQueueTivo] ;
		for (MTTiVo * tiVo in [tiVoManager tiVoList]) {
			if ([tiVo.tiVo.name compare: tivoName] == NSOrderedSame) {
				_tiVo = tiVo;
				break;
			}
		}
		if (!_tiVo) {
			self.tempTiVoName = tivoName;
		}
	}
	DDLogDetail(@"initWithCoder for %@",self);
	return self;
}

- (id)pasteboardPropertyListForType:(NSString *)type {
//	NSLog(@"QQQ:pboard Type: %@",type);
	if ([type compare:kMTTivoShowPasteBoardType] ==NSOrderedSame) {
		return  [NSKeyedArchiver archivedDataWithRootObject:self];
	} else {
		return nil;
	}
}
-(NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard {
	NSArray* result = [NSArray  arrayWithObjects: kMTTivoShowPasteBoardType, nil];  //NOT working yet
//	NSLog(@"QQQ:writeable Type: %@",result);
	return result;
}

- (NSPasteboardWritingOptions)writingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard {
	return 0;
}

+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard {
	return @[kMTTivoShowPasteBoardType];

}
+ (NSPasteboardReadingOptions)readingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard {
	if ([type compare:kMTTivoShowPasteBoardType] ==NSOrderedSame)
		return NSPasteboardReadingAsKeyedArchive;
	return 0;
}


#pragma  mark - parser methods

-(void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
	elementString = [NSMutableString new];
	if ([elementName compare:@"element"] != NSOrderedSame) {
		elementArray = [NSMutableArray new];
	}
}

-(void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
	[elementString appendString:string];
}

- (void)setValue:(id)value forUndefinedKey:(NSString *)key{
    //nothing to see here; just move along
	DDLogVerbose(@"Unrecognized key %@", key);
}

-(void) endElement:(NSString *)elementName item:(id) item {
	DDLogDetail(@" %@: %@",elementName, item);

}

-(void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
	if (parseTermMapping[elementName]) {
		elementName = parseTermMapping[elementName];
	}
	if ([elementName compare:@"element"] == NSOrderedSame) {
		[elementArray addObject:elementString];
	} else {
		id item;
		if (elementArray.count) {
			item = [NSArray arrayWithArray:elementArray];
		} else {
			item = elementString;
		}
		@try {
			[self setValue:item forKeyPath:elementName];
			[self endElement: elementName item: item];
		}
		@catch (NSException *exception) {
		}
		@finally {
		}
	}
}

-(void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
	_gotDetails = NO;
	DDLogMajor(@"Show: %@ Parser Error %@",self.showTitle, parseError);
}


//-(NSArray *) apmArguments {
//	NSMutableArray * apmArgs = [NSMutableArray array];
//
//	[apmArgs addObject:@"--overWrite"];
//	[apmArgs addObject:@"--stik"];
//	if (self.isMovie) {
//		[apmArgs addObject:@"Short Film"];
//	} else {
//		[apmArgs addObject:@"TV Show"];
//	}
//	if (self.episodeTitle.length>0) {
//		[apmArgs addObject:@"--title"];
//		[apmArgs addObject:self.episodeTitle];
//	}
//	if (self.episodeGenre.length>0) {
//		[apmArgs addObject:@"--grouping"];
//		[apmArgs addObject:self.episodeGenre];
//	}
//	if (self.originalAirDate.length>0) {
//		[apmArgs addObject:@"--year"];
//		[apmArgs addObject:self.originalAirDate];
//	} else if (self.movieYear.length>0) {
//		[apmArgs addObject:@"--year"];
//		[apmArgs addObject:self.movieYear];
//	}
//	
//	if (self.showDescription.length > 0) {
//		if (self.showDescription.length < 230) {
//			[apmArgs addObject:@"--description"];
//			[apmArgs addObject:self.showDescription];
//			
//		} else {
//			[apmArgs addObject:@"--longdesc"];
//			[apmArgs addObject:self.showDescription];
//		}
//	}
//	if (self.seriesTitle.length>0) {
//		[apmArgs addObject:@"--TVShowName"];
//		[apmArgs addObject:self.seriesTitle];
//		[apmArgs addObject:@"--artist"];
//		[apmArgs addObject:self.seriesTitle];
//		[apmArgs addObject:@"--albumArtist"];
//		[apmArgs addObject:self.seriesTitle];
//	}
//	if (self.episodeNumber.length>0) {
//		[apmArgs addObject:@"--TVEpisode"];
//		[apmArgs addObject:self.episodeNumber];
//	}
//	if (self.episode > 0) {
//		NSString * epString = [NSString stringWithFormat:@"%d",self.episode];
//		[apmArgs addObject:@"--TVEpisodeNum"];
//		[apmArgs addObject:epString];
//		[apmArgs addObject:@"--tracknum"];
//		[apmArgs addObject:epString];
//	} else if (self.episodeNumber.length>0) {
//		[apmArgs addObject:@"--TVEpisodeNum"];
//		[apmArgs addObject:self.episodeNumber];
//		[apmArgs addObject:@"--tracknum"];
//		[apmArgs addObject:self.episodeNumber];
//		
//	}
//	if (self.season > 0 ) {
//		NSString * seasonString = [NSString stringWithFormat:@"%d",self.season];
//		[apmArgs addObject:@"--TVSeasonNum"];
//		[apmArgs addObject:seasonString];		
//	}
//	if (self.stationCallsign) {
//		[apmArgs addObject:@"--TVNetwork"];
//		[apmArgs addObject:self.stationCallsign];
//	}
//	return apmArgs;
//}

#pragma mark - Custom Getters

-(NSString *)showKey
{
	return [NSString stringWithFormat:@"%@: %@",self.tiVoName,self.idString];
}
												  
-(NSString *) seasonEpisode {
    
    NSString *returnString = @"";
    if (_episode > 0) {
		if (_season > 0) {
			returnString = [NSString stringWithFormat:@"S%0.2dE%0.2d",_season,_episode ];
		} else {
			returnString = [NSString stringWithFormat:@"%d",_episode];
		}
     } else {
        returnString = _episodeNumber;
    }
    return returnString;
}

-(NSString *) seriesFromProgram:(NSString *) name {
    NSArray * nameParts = [name componentsSeparatedByString: @":"];
    if (nameParts.count == 0) return name;
    return [nameParts objectAtIndex:0];
}

-(NSString * ) seriesTitle {
    if (!_seriesTitle) {
        self.seriesTitle = [self seriesFromProgram:_showTitle];
    }
    return _seriesTitle;
}

-(BOOL) isMovie {
	BOOL value =  (self.movieYear.length > 0) ||
				  ([self.episodeID hasPrefix:@"MV"]) ||
					!(self.isEpisodic.boolValue ||
					  ((self.episodeTitle.length > 0) ||
					   (self.episode > 0) ||
					   (self.showLength < 70*60))) ;
	return value;
}

-(NSAttributedString *)attrStringFromDictionary:(id)nameList
{
    NSMutableString *returnString = [NSMutableString string];
    if ([nameList isKindOfClass:[NSArray class]]) {
        for (NSDictionary *name in nameList) {
            [returnString appendFormat:@"%@\n",[self nameString:name]];
        }
       	if (returnString.length > 0)[returnString deleteCharactersInRange:NSMakeRange(returnString.length-1, 1)];
		
    }
	return [[NSAttributedString alloc] initWithString:returnString attributes:@{NSFontAttributeName : [NSFont systemFontOfSize:11]}];
    
}

-(NSAttributedString *)attribDescription {
	NSAttributedString *attstring = [[NSAttributedString alloc] initWithString:@""];
	if (self.showDescription) {
		attstring = [[NSAttributedString alloc] initWithString:self.showDescription];
	}
	return attstring;
}

-(NSAttributedString *)actors
{
    return [self attrStringFromDictionary:_vActor];
}

-(NSAttributedString *)guestStars
{
    return [self attrStringFromDictionary:_vGuestStar];
}

-(NSAttributedString *)directors
{
    return [self attrStringFromDictionary:_vDirector];
}

-(NSAttributedString *)producers
{
    return [self attrStringFromDictionary:_vExecProducer];
}

-(NSString *)yearString
{
    return [NSString stringWithFormat:@"%d",_episodeYear];
}

-(NSString *)seasonString
{
	NSString *returnString = @"";
	if (_season > 0) {
		returnString = [NSString stringWithFormat:@"%d",_season];
	}
    return returnString;
}


-(MTTiVo *) tiVo {
	if (!_tiVo) {
		for (MTTiVo * possibleTiVo in tiVoManager.tiVoList) {
			if ([possibleTiVo.tiVo.name isEqualToString:self.tempTiVoName]) {
				self.tiVo = possibleTiVo;
				break;
			}
		}
	}
	return _tiVo;
}

-(const MP4Tags * ) metaDataTagsWithImage: (NSImage* ) image {
	const MP4Tags *tags = MP4TagsAlloc();
	uint8_t mediaType = 10;
	if (self.isMovie) {
		mediaType = 9;
	}
	MP4TagsSetMediaType(tags, &mediaType);
	if (self.episodeTitle.length>0) {
		MP4TagsSetName(tags,[self.episodeTitle cStringUsingEncoding:NSUTF8StringEncoding]);
	}
	if (self.episodeGenre.length>0) {
		MP4TagsSetGenre(tags,[self.episodeGenre cStringUsingEncoding:NSUTF8StringEncoding]);
	}
	if (self.originalAirDate.length>0) {
		MP4TagsSetReleaseDate(tags,[self.originalAirDate cStringUsingEncoding:NSUTF8StringEncoding]);
	} else if (self.movieYear.length>0) {
		MP4TagsSetReleaseDate(tags,[self.movieYear	cStringUsingEncoding:NSUTF8StringEncoding]);
	}
	
	if (self.showDescription.length > 0) {
		if (self.showDescription.length < 230) {
			MP4TagsSetDescription(tags,[self.showDescription cStringUsingEncoding:NSUTF8StringEncoding]);
			
		} else {
			MP4TagsSetLongDescription(tags,[self.showDescription cStringUsingEncoding:NSUTF8StringEncoding]);
		}
	}
	if (self.seriesTitle.length>0) {
		MP4TagsSetTVShow(tags,[self.seriesTitle cStringUsingEncoding:NSUTF8StringEncoding]);
		MP4TagsSetArtist(tags,[self.seriesTitle cStringUsingEncoding:NSUTF8StringEncoding]);
		MP4TagsSetAlbumArtist(tags,[self.seriesTitle cStringUsingEncoding:NSUTF8StringEncoding]);
	}
	if (self.episodeNumber.length>0) {
		uint32_t episodeNumber = [self.episodeNumber intValue];
		MP4TagsSetTVEpisode(tags, &episodeNumber);
	}
	if (self.episode > 0) {
		uint32_t episodeNumber = self.episode;
		MP4TagsSetTVEpisode(tags, &episodeNumber);
		//				NSString * epString = [NSString stringWithFormat:@"%d",self.episode];
		//				[apmArgs addObject:@"--tracknum"];
		//				[apmArgs addObject:epString];
	} else if (self.episodeNumber.length>0) {
		uint32_t episodeNumber =  [self.episodeNumber intValue];
		MP4TagsSetTVEpisode(tags, &episodeNumber);
		//				[apmArgs addObject:@"--tracknum"];
		//				[apmArgs addObject:self.episodeNumber];
		
	}
	if (self.season > 0 ) {
		uint32_t showSeason =  self.season;
		MP4TagsSetTVSeason(tags, &showSeason);
	}
	if (self.stationCallsign) {
		MP4TagsSetTVNetwork(tags, [self.stationCallsign cStringUsingEncoding:NSUTF8StringEncoding]);
	}
	
	if (image) {
		NSData *PNGData  = [NSBitmapImageRep representationOfImageRepsInArray: [image representations]
																	usingType:NSPNGFileType properties:nil];
		MP4TagArtwork artwork;
		
		artwork.data = (void *)[PNGData bytes];
		artwork.size = (uint32_t)[PNGData length];
		artwork.type = MP4_ART_PNG;
		
		MP4TagsAddArtwork(tags, &artwork);
	}
	
	return tags;
}

-(NSString *)showDateString
{
	static NSDateFormatter *dateFormat;
	if(!dateFormat) {
		dateFormat = [[NSDateFormatter alloc] init] ;
		[dateFormat setDateStyle:NSDateFormatterShortStyle];
		[dateFormat setTimeStyle:NSDateFormatterShortStyle] ;
	}
//	[dateFormat setTimeStyle:NSDateFormatterNoStyle];
	return [dateFormat stringFromDate:_showDate];
}

-(NSString *)showMediumDateString
{
	static NSDateFormatter *dateFormat;
	if(!dateFormat) {
		dateFormat = [[NSDateFormatter alloc] init] ;
		[dateFormat setDateStyle:NSDateFormatterMediumStyle];
		[dateFormat setTimeStyle:NSDateFormatterShortStyle] ;
	}
	//	[dateFormat setTimeStyle:NSDateFormatterNoStyle];
	return [dateFormat stringFromDate:_showDate];
}
												  
-(NSString *)checkString:(BOOL) test {
  return test ? @"✔" : @"";
}
											  
-(NSString*) lengthString {
	NSInteger length = (_showLength+30)/60; //round up to nearest minute;
	return [NSString stringWithFormat:@"%ld:%0.2ld",length/60,length % 60];
}
												  
-(NSString*) isQueuedString {
  return [self checkString: _isQueued];
}
												  
-(NSString*) isHDString {
	return [self checkString:_isHD.boolValue];
}

-(NSString*) imageString {
	if (self.protectedShow.boolValue && !self.inProgress.boolValue) {
		if (self.fileSize > 0) {
			return @"copyright";
		} else {
			//not loaded yet
			return @"questionmark";
		}
	}
	if (_imageString.length) {
		return _imageString;
	} else {
		return @"recent-recording";
	}
}

-(NSString*) idString {
	return[NSString stringWithFormat:@"%d", _showID ];
}
												  
-(NSString*) sizeString {
  
  if (_fileSize >= 1000000000) {
	  return[NSString stringWithFormat:@"%0.1fGB",_fileSize/(1000000000)];
  } else if (_fileSize > 0) {
	  return[NSString stringWithFormat:@"%ldMB",((NSInteger)_fileSize)/(1000000) ];
  } else {
	  return @"-";
  }
}

-(NSString *) combinedChannelString {
	if (!self.channelString) return @"";
	return  [NSString stringWithFormat:@"%@-%@ %@",
			 self.stationCallsign,
			 self.channelString,
			 self.isHD.boolValue? @"HD": @""];
}
-(NSString *) episodeGenre {
    //iTunes says "there can only be one", so pick the first we see.
    NSCharacterSet * quotes = [NSCharacterSet characterSetWithCharactersInString:@"\""];
    NSString * firstGenre = nil;
    if (_vSeriesGenre.count > 0) firstGenre = [_vSeriesGenre objectAtIndex:0];
	else if (_vProgramGenre.count > 0) firstGenre = [_vProgramGenre objectAtIndex:0];
	else firstGenre = @"";
    return [firstGenre stringByTrimmingCharactersInSet:quotes];
}

-(NSString *) tiVoName {
	if (_tiVo) {
		return _tiVo.tiVo.name;
	} else {
		return self.tempTiVoName;
	}
}

-(NSString *) episodeID {

	if (![_programId hasPrefix:@"MV"] && [_programId hasSuffix:@"0000"] ) {
			NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init] ;
			[dateFormat setDateStyle:NSDateFormatterShortStyle];
			[dateFormat setTimeStyle:NSDateFormatterNoStyle] ;
			return [NSString stringWithFormat: @"%@-%@",_programId, [dateFormat stringFromDate: _showDate] ];
	} else {
		return _programId;
	}
}

												  

#pragma mark - Custom Setters; many for parsing


-(void) setShowTime: (NSString *) newTime {
	if (newTime != _showTime) {
        _showTime = newTime;
        NSDate *newDate =[_showTime dateForRFC3339DateTimeString];
        if (newDate) {
            self.showDate = newDate;
        }
		//        NSLog(@"converting %@ from: %@ to %@ ", self.showTitle, newTime, self.showDate);
    }
}
-(void)setMovieYear:(NSString *)movieYear {
	if (movieYear != _movieYear) {
		_movieYear = movieYear;
		if (self.originalAirDateNoTime.length == 0) {
			_originalAirDateNoTime = movieYear;
		}
	}
}

-(void) setImageString:(NSString *)imageString {
	if (imageString != _imageString) {
		_imageString = imageString;
		_isSuggestion = [@"suggestion-recording" isEqualToString:imageString];
	}
}

-(void)setOriginalAirDate:(NSString *)originalAirDate
{
	if (originalAirDate != _originalAirDate) {
		_originalAirDate = originalAirDate;
		if (originalAirDate.length > 4) {
			_episodeYear = [[originalAirDate substringToIndex:4] intValue];
		}
		if (originalAirDate.length >= 10) {
			_originalAirDateNoTime = [originalAirDate substringToIndex:10];
		} else if (originalAirDate.length > 0) {
			_originalAirDateNoTime = originalAirDate;
		} else {
			_originalAirDateNoTime = _movieYear;
		}
	}
}

-(void)setEpisodeNumber:(NSString *)episodeNumber
{
	if (episodeNumber != _episodeNumber) {  // this check is mandatory
        _episodeNumber = episodeNumber;
		if (episodeNumber.length) {
			long l = episodeNumber.length;
			if (l > 2) {
				int epDigits = (l > 4) ? 3:2; 
					_episode = [[episodeNumber substringFromIndex:l-epDigits] intValue];
					_season = [[episodeNumber substringToIndex:l-epDigits] intValue];
			} else {
				_episode = [episodeNumber intValue];
			}
		}
	}
	
}

-(void)playVideo:(NSString *)path
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];

}

-(void)revealInFinder:(NSArray *)paths
{
   	NSMutableArray * showURLs = [NSMutableArray arrayWithCapacity:paths.count];
	for (NSString *fileName in paths) {
		NSURL * showURL = [NSURL fileURLWithPath:fileName];
		if (showURL) {
			[showURLs addObject:showURL];
		}
	}
	if (showURLs.count > 0) {
		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:showURLs];
	}
}

-(void)setInProgress:(NSNumber *)inProgress
{
  if (_inProgress != inProgress) {
	  _inProgress = inProgress;
	  if ([_inProgress boolValue]) {
		  self.protectedShow = @(YES);
	  }
  }
}


-(BOOL)reallySetShowTitle: (NSString *) showTitle {
	if (_showTitle != showTitle) {
		_showTitle = showTitle;
		return YES;
	}
	return NO;
}

-(void)setShowTitle:(NSString *)showTitle {
	if ([self reallySetShowTitle:showTitle] && showTitle) {
		NSRange pos = [showTitle rangeOfString: @": "];
		//Normally this is built from episode/series; but if we got showtitle from
		//"old" queue, we'd like to temporarily display eps/series
		if (pos.location == NSNotFound) {
			if (_seriesTitle.length == 0) {
				_seriesTitle = showTitle;
			}
		} else {
			if (_seriesTitle.length == 0) {
				_seriesTitle = [showTitle substringToIndex:pos.location];
			}
			if (_episodeTitle.length == 0) {
				_episodeTitle = [showTitle substringFromIndex:pos.location+pos.length];
			}
		}
	}
}

-(void)setSeriesTitle:(NSString *)seriesTitle
{
	if (_seriesTitle != seriesTitle) {
		_seriesTitle = seriesTitle;
		if (_episodeTitle.length > 0 ) {
			[self reallySetShowTitle:[NSString stringWithFormat:@"%@: %@",_seriesTitle, _episodeTitle]];
		} else {
			[self reallySetShowTitle: _seriesTitle];
		}
	}
}

-(void)setEpisodeTitle:(NSString *)episodeTitle
{
	if (_episodeTitle != episodeTitle) {
		_episodeTitle = episodeTitle;
		if (_episodeTitle.length > 0 ) {
			[self reallySetShowTitle:[NSString stringWithFormat:@"%@: %@",_seriesTitle, _episodeTitle]];
		} else {
			[self reallySetShowTitle: _seriesTitle];
		}
	}
}

-(void)setShowDescription:(NSString *)showDescription
{
    NSString * tribuneCopyright = @" Copyright Tribune Media Services, Inc.";
	if (_showDescription == showDescription) {
		return;
	}
    if ([showDescription hasSuffix: tribuneCopyright]){
        _showDescription = [showDescription substringToIndex:showDescription.length -tribuneCopyright.length];
    } else {
        _showDescription = showDescription;

    }
}

-(void)setVActor:(NSArray *)vActor
{
	if (_vActor == vActor || ![vActor isKindOfClass:[NSArray class]]) {
		return;
	}
	_vActor = [self parseNames: vActor ];
}

-(void)setVGuestStar:(NSArray *)vGuestStar
{
	if (_vGuestStar == vGuestStar || ![vGuestStar isKindOfClass:[NSArray class]]) {
		return;
	}
	_vGuestStar = [self parseNames: vGuestStar ];
}

-(void)setVDirector:(NSArray *)vDirector
{
	if (_vDirector == vDirector || ![vDirector isKindOfClass:[NSArray class]]) {
		return;
	}
	_vDirector = [self parseNames: vDirector ];
}

-(void)setVExecProducer:(NSArray *)vExecProducer
{
	if (_vExecProducer == vExecProducer || ![vExecProducer isKindOfClass:[NSArray class]]) {
		return;
	}
	_vExecProducer = [self parseNames:vExecProducer];
}


-(void)setVProgramGenre:(NSArray *)vProgramGenre
{
	if (_vProgramGenre == vProgramGenre || ![vProgramGenre isKindOfClass:[NSArray class]]) {
		return;
	}
	_vProgramGenre = vProgramGenre;
}

-(void)setVSeriesGenre:(NSArray *)vSeriesGenre{
	if (_vSeriesGenre == vSeriesGenre || ![vSeriesGenre isKindOfClass:[NSArray class]]) {
		return;
	}
	_vSeriesGenre = vSeriesGenre;
}

#pragma mark - Memory Management

-(void)dealloc
{
    self.showTitle = nil;
    self.showDescription = nil;
    self.tiVo = nil;
	if (elementString) {
        elementString = nil;
	}
	if (elementArray) {
        elementArray = nil;
	}
}

-(NSString *)description
{
    return [NSString stringWithFormat:@"%@ (%@)%@",_showTitle,self.tiVoName,[_protectedShow boolValue]?@"-Protected":@""];
}


@end

