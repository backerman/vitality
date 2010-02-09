/*
 This file is part of Mac Eve Tools.
 
 Mac Eve Tools is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 Mac Eve Tools is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with Mac Eve Tools.  If not, see <http://www.gnu.org/licenses/>.
 
 Copyright Matt Tyson, 2009.
 */

#import "CCPDatabase.h"
#import "CCPGroup.h"
#import "CCPCategory.h"
#import "CCPType.h"
#import "CCPTypeAttribute.h"

#import "METShip.h"

#import "Helpers.h"
#import "macros.h"
#import "SkillPair.h"

#import "Config.h"

#import <sqlite3.h>


@implementation CCPDatabase

@synthesize lang;

-(CCPDatabase*) initWithPath:(NSString*)dbpath
{
	if(self = [super initWithPath:dbpath]){
		[self openDatabase];
		tran_stmt = NULL;
		lang = [[Config sharedInstance]dbLanguage];
	}
	return self;
}

-(void) dealloc
{
	[self closeDatabase];
	[super dealloc];
}

-(void) closeDatabase
{
	if(tran_stmt != NULL){
		sqlite3_finalize(tran_stmt);
		tran_stmt = NULL;
	}
	
	[super closeDatabase];
}

-(NSInteger) dbVersion
{
	const char query[] =
		"SELECT versionNum FROM version;";
	
	sqlite3_stmt *read_stmt;
	NSInteger version = -1;
	
	int rc;
	
	rc = sqlite3_prepare_v2(db,query, (int)sizeof(query), &read_stmt, NULL);
	
	if(rc != SQLITE_OK){
		return -1;
	}
	
	if(sqlite3_step(read_stmt) == SQLITE_ROW){
		version = sqlite3_column_nsint(read_stmt,0);
	}
	
	sqlite3_finalize(read_stmt);
	
	return version;
}

-(NSString*) dbName
{
	const char query[] = 
		"SELECT versionName FROM version;";
	sqlite3_stmt *read_stmt;
	int rc;
	NSString *result = @"N/A";
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
		return result;
	}
	
	if(sqlite3_step(read_stmt) == SQLITE_ROW){
		result = sqlite3_column_nsstr(read_stmt,0);
	}
	
	sqlite3_finalize(read_stmt);
	
	return result;
}

-(CCPCategory*) category:(NSInteger)categoryID
{
	const char query[] = 
		"SELECT categoryID, categoryName, graphicID FROM invCategories WHERE categoryID = ? "
		"ORDER BY categoryName;";
	sqlite3_stmt *read_stmt;
	int rc;
	
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
		NSLog(@"%s: sqlite error\n",__func__);
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,categoryID);
	
	CCPCategory *cat = nil;
	
	if(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger cID = sqlite3_column_nsint(read_stmt,0);
		const unsigned char *str = sqlite3_column_text(read_stmt,1);
		NSString *cName = [NSString stringWithUTF8String:(const char*)str];
		NSInteger gID = sqlite3_column_nsint(read_stmt,2);
	
		cat = [[CCPCategory alloc]initWithCategory:cID
										   graphic:gID 
											  name:cName
										  database:self];
		[cat autorelease];
	}
	
	sqlite3_finalize(read_stmt);
	
	return cat;
}

-(NSInteger) categoryCount
{
	const char query[] = "SELECT COUNT(*) FROM invCategories;";
	return [self performCount:query];
}

-(NSArray*) categoriesInDB
{
	return nil;
}

#pragma mark groups

-(NSInteger) groupCount:(NSInteger)categoryID
{
	NSLog(@"Insert code here");
	return 0;
}


-(CCPGroup*) group:(NSInteger)groupID
{
	const char query[] = "SELECT groupID, categoryID, groupName, graphicID FROM invGroups WHERE groupID = ?;";
	sqlite3_stmt *read_stmt;
	CCPGroup *group = nil;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
		NSLog(@"%s: sqlite error\n",__func__);
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,groupID);
	
	if(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger groupID,categoryID,graphicID;
		NSString *groupName;
		const char *str;
		
		groupID = sqlite3_column_nsint(read_stmt,0);
		categoryID = sqlite3_column_nsint(read_stmt,1);
		groupName = sqlite3_column_nsstr(read_stmt,2);
		graphicID = sqlite3_column_nsint(read_stmt,3);
		
		group = [[CCPGroup alloc] initWithGroup:groupID
									   category:categoryID 
										graphic:graphicID
									  groupName:groupName
									   database:self];
		[group autorelease];
	}
	
	sqlite3_finalize(read_stmt);
	
	return group;
}

-(NSString*) translation:(NSInteger)keyID 
			   forColumn:(NSInteger)columnID
				fallback:(NSString*)fallback
{
	const char query[] = 
		"SELECT text "
		"FROM trnTranslations "
		"WHERE tcID = ? AND keyID = ? AND languageID = ?;";
	NSString *result = nil;
	
	if(tran_stmt == NULL){
		sqlite3_prepare_v2(db,query,(int)sizeof(query),&tran_stmt,NULL);
	}
	
	sqlite3_bind_nsint(tran_stmt,1,columnID);
	sqlite3_bind_nsint(tran_stmt,2,keyID);
	sqlite3_bind_text(tran_stmt,3, langCodeForId(lang),2, NULL);
	
	int rc = sqlite3_step(tran_stmt);
	if((rc == SQLITE_DONE) || (rc == SQLITE_ROW)){
		result = sqlite3_column_nsstr(tran_stmt,0); //returns an empty string on failure.
	}else{
		NSLog(@"Sqlite error - %s",__func__);
	}
	
	sqlite3_reset(tran_stmt);
	sqlite3_clear_bindings(tran_stmt);
	
	return [result length] > 0 ? result : fallback;
}

-(NSArray*) groupsInCategory:(NSInteger)categoryID
{
	const char query[] = 
		"SELECT groupID, categoryID, groupName, graphicID " 
		"FROM invGroups WHERE categoryID = ? "
		"ORDER BY groupName;";
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
		NSLog(@"%s: sqlite error\n",__func__);
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,categoryID);
	
	NSMutableArray *array = [[[NSMutableArray alloc]init]autorelease];
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger groupID,categoryID,graphicID;
		NSString *groupName = nil;
		CCPGroup *group;
		
		groupID = sqlite3_column_nsint(read_stmt,0);
		categoryID = sqlite3_column_nsint(read_stmt,1);
		groupName = sqlite3_column_nsstr(read_stmt,2);
		
		if(lang != l_EN){
			groupName = [self translation:groupID forColumn:TRN_GROUP_NAME fallback:groupName];
		}
		
		graphicID = sqlite3_column_nsint(read_stmt,3);
		
		group = [[CCPGroup alloc]initWithGroup:groupID
									  category:categoryID 
									   graphic:graphicID
									 groupName:groupName
									  database:self];
		[array addObject:group];
		[group release];		
	}
	
	sqlite3_finalize(read_stmt);
	
	return array;
}

#pragma mark typeSMInt

-(NSInteger) typeCount:(NSInteger)groupID
{
	const char query[] = "SELECT COUNT(*) FROM invTypes WHERE typeID = ?;";
	NSLog(@"Insert code here");
	return 0;
}

-(CCPType*) type:(NSInteger)typeID
{
	NSLog(@"Insert code here");
	return nil;
}

-(NSArray*) typesInGroup:(NSInteger)groupID
{
	const char query[] = 
		"SELECT typeID, groupID, graphicID, raceID, marketGroupID,radius, mass, volume, capacity,"
		"basePrice, typeName, description FROM invTypes WHERE groupID = ? "
		"ORDER BY typeName;";
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
		NSLog(@"%s: sqlite error\n",__func__);
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,groupID);
	
	NSMutableArray *array = [[[NSMutableArray alloc]init]autorelease];
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		
		NSInteger typeID = sqlite3_column_nsint(read_stmt,0);
		NSString *description = sqlite3_column_nsstr(read_stmt,11);
		NSString *typeName = sqlite3_column_nsstr(read_stmt,10);
		
		if(lang != l_EN){
			description = [self translation:typeID forColumn:TRN_TYPE_DESCRIPTION fallback:description];
			typeName = [self translation:typeID forColumn:TRN_TYPE_NAME fallback:typeName];
		}
		
		CCPType *type = [[CCPType alloc]
						 initWithType:sqlite3_column_nsint(read_stmt,0)
						 group:sqlite3_column_nsint(read_stmt,1)
						 graphic:sqlite3_column_nsint(read_stmt,2)
						 race:sqlite3_column_nsint(read_stmt,3)
						 marketGroup:sqlite3_column_nsint(read_stmt,4)
						 radius:sqlite3_column_double(read_stmt,5)
						 mass:sqlite3_column_double(read_stmt,6)
						 volume:sqlite3_column_double(read_stmt,7)
						 capacity:sqlite3_column_double(read_stmt,8)
						 basePrice:sqlite3_column_double(read_stmt,9)
						 typeName:typeName
						 typeDesc:description
						 database:self];
		
		[array addObject:type];
		[type release];		
	}
	
	sqlite3_finalize(read_stmt);
	
	return array;
}

-(NSArray*) prereqForType:(NSInteger)typeID
{
	const char query[] = 
		"SELECT skillTypeID, skillLevel FROM typePrerequisites WHERE typeID = ? ORDER BY skillOrder;";
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
		NSLog(@"%s: sqlite error\n",__func__);
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,typeID);
	
	NSMutableArray *array = [[[NSMutableArray alloc]init]autorelease];
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger skillTypeID = sqlite3_column_nsint(read_stmt,0);
		NSInteger skillLevel = sqlite3_column_nsint(read_stmt,1);
		SkillPair *pair = [[SkillPair alloc]initWithSkill:
						   [NSNumber numberWithInteger:skillTypeID] 
												level:skillLevel];
		[array addObject:pair];
		[pair release];
	}
	
	sqlite3_finalize(read_stmt);
	
	return array;
}

-(BOOL) parentForTypeID:(NSInteger)typeID parentTypeID:(NSInteger*)parent metaGroupID:(NSInteger*)metaGroup
{
	const char query[] = 
		"SELECT parentTypeID, metaGroupID FROM invMetaTypes WHERE typeID = ?;";
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
		NSLog(@"%s: sqlite error\n",__func__);
		return NO;
	}
	
	sqlite3_bind_nsint(read_stmt,1,typeID);
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		if(parent != NULL){
			*parent = sqlite3_column_nsint(read_stmt,0);
		}
		if(metaGroup != NULL){
			*metaGroup = sqlite3_column_nsint(read_stmt,1);
		}
	}
	
	sqlite3_finalize(read_stmt);
	
	return YES;
}

-(NSInteger) metaLevelForTypeID:(NSInteger)typeID
{
	NSInteger metaLevel = -1;
	const char query[] =
		"SELECT COALESCE(valueInt,valueFloat) FROM dgmTypeAttributes WHERE attributeID = 633 AND typeID = ?;";
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
		NSLog(@"%s: sqlite error\n",__func__);
		return -1;
	}
	
	sqlite3_bind_nsint(read_stmt,1,typeID);
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		metaLevel = sqlite3_column_nsint(read_stmt,0);
	}
	
	sqlite3_finalize(read_stmt);
	
	return metaLevel;
}

-(BOOL) isPirateShip:(NSInteger)typeID
{
	BOOL result = NO;
	
	const char query[] = 
		"SELECT COALESCE(valueInt,valueFloat) FROM dgmTypeAttributes WHERE attributeID = 793 AND typeID = ?;";
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query), &read_stmt, NULL);
	if(rc != SQLITE_OK){
		NSLog(@"%s: sqlite error\n",__func__);
		return -1;
	}
	
	sqlite3_bind_nsint(read_stmt,1,typeID);
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		result = YES;
	}
	
	sqlite3_finalize(read_stmt);
	
	return result;
}

-(NSDictionary*) typeAttributesForTypeID:(NSInteger)typeID
{
	const char query[] =
		"SELECT at.graphicID, at.attributeID, at.displayName, un.displayName, ta.valueInt, ta.valueFloat "
		"FROM dgmTypeAttributes ta, dgmAttributeTypes at, eveUnits un "
		"WHERE at.attributeID = ta.attributeID "
		"AND un.unitID = at.unitID "
		"AND ta.typeID = ?;";

	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db, query, (int)sizeof(query), &read_stmt, NULL);
	if(rc != SQLITE_OK){
		NSLog(@"%s: SQLite error",__func__);
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,typeID);
	
	NSMutableDictionary *attributes = [[[NSMutableDictionary alloc]init]autorelease];
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger graphicID = sqlite3_column_nsint(read_stmt,0);
		NSInteger attributeID = sqlite3_column_nsint(read_stmt,1);
		NSString *dispName = sqlite3_column_nsstr(read_stmt, 2);
		NSString *unitDisp = sqlite3_column_nsstr(read_stmt, 3);
		
		NSInteger vInt;
		
		if(sqlite3_column_type(read_stmt,4) == SQLITE_NULL){
			vInt = NSIntegerMax;
		}else{
			vInt = sqlite3_column_nsint(read_stmt,4);
		}
		
		CGFloat vFloat;
		
		if(sqlite3_column_type(read_stmt, 5) == SQLITE_NULL){
			vFloat = CGFLOAT_MAX;
		}else{
			vFloat = (CGFloat) sqlite3_column_double(read_stmt, 5);
		}
		
		NSNumber *attrNum = [NSNumber numberWithInteger:attributeID];
		
		CCPTypeAttribute *ta = [CCPTypeAttribute createTypeAttribute:attributeID
															dispName:dispName 
														 unitDisplay:unitDisp
														   graphicId:graphicID 
															valueInt:vInt 
														  valueFloat:vFloat];
		
		[attributes setObject:ta forKey:attrNum];
	}
	
	sqlite3_finalize(read_stmt);
	
	return attributes;
}

-(METShip*) shipForTypeID:(NSInteger)typeID
{
	CCPType *shipType = [self type:typeID];
	NSDictionary *typeAttr = [self typeAttributesForTypeID:typeID];
}

-(NSArray*) attributeForType:(NSInteger)typeID groupBy:(enum AttributeTypeGroups)group
{
	const char query[] =
	/*
		"SELECT at.graphicID, at.displayName, ta.valueInt, "
			"ta.valueFloat, at.attributeID, un.displayName "
		"FROM metAttributeTypes at, dgmTypeAttributes ta, eveUnits un "
		"WHERE at.attributeID = ta.attributeID "
		"AND at.unitID = un.unitID "
		"AND typeID = ? "
		"AND at.displayType = ?;";*/
	
	"SELECT at.graphicID, COALESCE(at.displayName,at.attributeName), ta.valueInt, "
		"ta.valueFloat, at.attributeID, un.displayName "
	"FROM dgmTypeAttributes ta, metAttributeTypes at LEFT OUTER JOIN eveUnits un ON at.unitID = un.unitID "
	"WHERE at.attributeID = ta.attributeID "
	"AND typeID = ? "
	"AND at.displayType = ?;";
	
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db, query, (int)sizeof(query), &read_stmt, NULL);
	if(rc != SQLITE_OK){
		NSLog(@"%s: query error",__func__);
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,typeID);
	sqlite3_bind_nsint(read_stmt,2,group);
	
	NSMutableArray *attributes = [[[NSMutableArray alloc]init]autorelease];
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger graphicID = sqlite3_column_nsint(read_stmt,0);
		NSString *displayName = sqlite3_column_nsstr(read_stmt,1);
		NSInteger attrID = sqlite3_column_nsint(read_stmt,4);
		NSString *unitDisplay = sqlite3_column_nsstr(read_stmt,5);
		
		NSInteger vInt;
		
		if(sqlite3_column_type(read_stmt,2) == SQLITE_NULL){
			vInt = NSIntegerMax;
		}else{
			vInt = sqlite3_column_nsint(read_stmt,2);
		}
		
		CGFloat vFloat;
		
		if(sqlite3_column_type(read_stmt, 3) == SQLITE_NULL){
			vFloat = CGFLOAT_MAX;
		}else{
			vFloat = (CGFloat) sqlite3_column_double(read_stmt, 3);
		}
		
		CCPTypeAttribute *ta = [CCPTypeAttribute createTypeAttribute:attrID
															dispName:displayName 
														 unitDisplay:unitDisplay
														   graphicId:graphicID 
															valueInt:vInt 
														  valueFloat:vFloat];
		
		//[attributes setObject:ta forKey:[NSNumber numberWithInteger:attrID]];
		[attributes addObject:ta];
	}
	
	sqlite3_finalize(read_stmt);
	
	if([attributes count] == 0){
		return nil;
	}
	
	return attributes;
}

//select ta.*,at.attributeName from dgmTypeAttributes ta INNER JOIN dgmAttributeTypes at ON ta.attributeID = at.attributeID where typeID = 17636;

@end
