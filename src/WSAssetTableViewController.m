//
//  WSAssetTableViewController.m
//  WSAssetPickerController
//
//  Created by Wesley Smith on 5/12/12.
//  Copyright (c) 2012 Wesley D. Smith. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import <Nimbus/NIDebuggingTools.h>
#import "WSAssetTableViewController.h"
#import "WSAssetPickerState.h"
#import "WSAssetsTableViewCell.h"
#import "NSData+SSToolkitAdditions.h"
#import "MBProgressHUD.h"


static NSString *const kWSSendImageTempDir = @"send_image_temp";

@interface UIImage (YZH)

- (UIImage *)imageWithScale:(CGFloat)scale;

@end


@implementation UIImage (YZH)


- (UIImage *)imageWithScale:(CGFloat)scale {
  UIGraphicsBeginImageContext(CGSizeMake(self.size.width * scale, self.size.height * scale));
  [self drawInRect:CGRectMake(0, 0, self.size.width * scale, self.size.height * scale)];
  UIImage *scaledImage = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();


  return scaledImage;
}
@end


#define ASSET_WIDTH_WITH_PADDING 79.0f

@interface WSAssetTableViewController () <WSAssetsTableViewCellDelegate>
@property(nonatomic, strong) NSMutableArray *fetchedAssets;
@property(nonatomic, readonly) NSInteger assetsPerRow;
@property(nonatomic, strong) UILabel *selectedPhotosNumLabel;
@end


@implementation WSAssetTableViewController {
  __weak UIBarButtonItem *_doneBarButtonItem;
  __block NSUInteger _resizingImageNumber;
  BOOL _doneButtonClicked;
}

@synthesize assetPickerState = _assetPickerState;
@synthesize assetsGroup = _assetsGroup;
@synthesize fetchedAssets = _fetchedAssets;
@synthesize assetsPerRow = _assetsPerRow;


#pragma mark - View Lifecycle

#define TABLE_VIEW_INSETS UIEdgeInsetsMake(2, 0, 2, 0);

- (void)loadView {
  [super loadView];

  _resizingImageNumber = 0;

  UIBarButtonItem *numBarButtonItem   = [[UIBarButtonItem alloc] initWithCustomView:self.selectedPhotosNumLabel];
  UIBarButtonItem *spaceBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
  UIBarButtonItem *doneBarButtonItem  = [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(doneButtonAction:)];
  _doneBarButtonItem = doneBarButtonItem;
  _doneBarButtonItem.enabled = NO;

  [self.navigationController setToolbarItems:@[numBarButtonItem, spaceBarButtonItem, doneBarButtonItem] animated:YES];
  [self.navigationController.toolbar setBarStyle:UIBarStyleBlackOpaque];

}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];

  self.wantsFullScreenLayout = YES;

  // Setup the toolbar if there are items in the navigationController's toolbarItems.
  if (self.navigationController.toolbarItems.count > 0) {
    self.toolbarItems = self.navigationController.toolbarItems;
    [self.navigationController setToolbarHidden:NO animated:YES];
  }

  self.assetPickerState.state = WSAssetPickerStatePickingAssets;

}

- (void)viewWillDisappear:(BOOL)animated {
  // Hide the toolbar in the event it's being displayed.
  if (self.navigationController.toolbarItems.count > 0) {
    [self.navigationController setToolbarHidden:YES animated:YES];
  }

  [super viewWillDisappear:animated];
}


- (void)viewDidLoad {
  self.navigationItem.title = @"Loading";

  UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
  cancelButton.frame = CGRectMake(0.0f, 0.0f, 40.0f, 40.0f);
  [cancelButton setImage:[UIImage imageNamed:@"bbs-cancel"] forState:UIControlStateNormal];
  [cancelButton addTarget:self action:@selector(cancelAction:) forControlEvents:UIControlEventTouchUpInside];

  //    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
  //                                                                                           target:self
  //                                                                                           action:@selector(cancelButtonAction:)];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:cancelButton];

  UIButton *backButton = [UIButton buttonWithType:UIButtonTypeCustom];
  [backButton setFrame:CGRectMake(0.0f, 0.0f, 36.0f, 30.0f)];
  [backButton setImage:[UIImage imageNamed:@"back.png"] forState:UIControlStateNormal];
  [backButton addTarget:self action:@selector(_pop:) forControlEvents:UIControlEventTouchDown];

  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:backButton];

  // TableView configuration.
  self.tableView.contentInset = TABLE_VIEW_INSETS;
  self.tableView.separatorColor  = [UIColor clearColor];
  self.tableView.allowsSelection = NO;


  // Fetch the assets.
  [self fetchAssets];
}

- (IBAction)_pop:(id)sender {
  [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Getters

- (NSMutableArray *)fetchedAssets {
  if (!_fetchedAssets) {
    _fetchedAssets = [NSMutableArray array];
  }
  return _fetchedAssets;
}

- (NSInteger)assetsPerRow {
  return MAX(1, (NSInteger) floorf(self.tableView.contentSize.width / ASSET_WIDTH_WITH_PADDING));
}

- (UILabel *)selectedPhotosNumLabel {
  if (!_selectedPhotosNumLabel) {
    _selectedPhotosNumLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 200.0f, 20.0f)];

    _selectedPhotosNumLabel.textColor       = [UIColor whiteColor];
    _selectedPhotosNumLabel.text            = @"可以选择上传多张图片";
    _selectedPhotosNumLabel.backgroundColor = [UIColor clearColor];
    _selectedPhotosNumLabel.font            = [UIFont systemFontOfSize:14.0f];

  }

  return _selectedPhotosNumLabel;
}

#pragma mark - Rotation

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
  [self.tableView reloadData];
}


#pragma mark - Fetching Code

- (void)fetchAssets {
  // TODO: Listen to ALAssetsLibrary changes in order to update the library if it changes.
  // (e.g. if user closes, opens Photos and deletes/takes a photo, we'll get out of range/other error when they come back.
  // IDEA: Perhaps the best solution, since this is a modal controller, is to close the modal controller.

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

    [self.assetsGroup enumerateAssetsWithOptions:NSEnumerationReverse usingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {

      if (!result || index == NSNotFound) {

        dispatch_async(dispatch_get_main_queue(), ^{
          [self scrollToBottom:nil];
          self.navigationItem.title = [NSString stringWithFormat:@"%@", [self.assetsGroup valueForProperty:ALAssetsGroupPropertyName]];
        });

        return;
      }

      WSAssetWrapper *assetWrapper = [[WSAssetWrapper alloc] initWithAsset:result];

      dispatch_async(dispatch_get_main_queue(), ^{

        [self.fetchedAssets insertObject:assetWrapper atIndex:0];

      });

    }];
  });


  [self performSelector:@selector(scrollToBottom:) withObject:nil afterDelay:0.5];
}

- (IBAction)scrollToBottom:(id)sender {
  [self.tableView reloadData];
  NSInteger rowNum = [self.tableView numberOfRowsInSection:0];

  if (rowNum > 5) {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:rowNum - 1 inSection:0];

    [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionBottom animated:NO];
  }

}

#pragma mark - Actions

- (void)doneButtonAction:(id)sender {

  _doneButtonClicked = YES;

  NIDINFO(@"[Agassi]: done button action _resizingImageNumber=%d",_resizingImageNumber);
  if (_resizingImageNumber == 0) {
    MBProgressHUD *hud = [MBProgressHUD HUDForView:self.navigationController.view];

    if (hud) {
      [hud hide:NO];
    }

    self.assetPickerState.state = WSAssetPickerStatePickingDone;
  }else {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
    [hud setLabelText:@"处理中..."];

  }

}

- (IBAction)cancelAction:(id)sender {
  [self dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - WSAssetsTableViewCellDelegate Methods

- (BOOL)assetsTableViewCell:(WSAssetsTableViewCell *)cell shouldSelectAssetAtColumn:(NSUInteger)column {
  BOOL shouldSelectAsset = (self.assetPickerState.selectionLimit == 0 ||
      (self.assetPickerState.selectedCount < self.assetPickerState.selectionLimit));

  NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
  NSUInteger assetIndex = (NSUInteger) (indexPath.row * self.assetsPerRow + column);

  WSAssetWrapper *assetWrapper = [self.fetchedAssets objectAtIndex:assetIndex];

  if ((shouldSelectAsset == NO) && (assetWrapper.isSelected == NO))
    self.assetPickerState.state = WSAssetPickerStateSelectionLimitReached;
  else
    self.assetPickerState.state = WSAssetPickerStatePickingAssets;

  return shouldSelectAsset;
}

- (void)assetsTableViewCell:(WSAssetsTableViewCell *)cell didSelectAsset:(BOOL)selected atColumn:(NSUInteger)column {
  NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];

  // Calculate the index of the corresponding asset.
  NSUInteger assetIndex = (NSUInteger) (indexPath.row * self.assetsPerRow + column);

  __block WSAssetWrapper *assetWrapper = [self.fetchedAssets objectAtIndex:assetIndex];

  if(selected) assetWrapper.tempPhotoPath = @"";

  assetWrapper.selected = selected;

  if (selected) {

    dispatch_queue_t queue = dispatch_queue_create("resizingImage", NULL);
    dispatch_async( queue , ^{
      UIImage  *scaleImage    = [self resizeAndSaveImage:assetWrapper.asset];
      NSString *tempImagePath = [self pathWithImageSaved:scaleImage];

      ++_resizingImageNumber;

      NIDINFO(@"[Agassi]: dispatch sub queue _resizingImageNumber=%d",_resizingImageNumber);
      assetWrapper.tempPhotoPath = tempImagePath;

      dispatch_async(dispatch_get_main_queue(), ^{

        --_resizingImageNumber;

        NIDINFO(@"[Agassi]: dispatch main queue _resizingImageNumber=%d\ntemp path=%@",_resizingImageNumber, tempImagePath);

        [self.assetPickerState changeSelectionState:selected forAsset:assetWrapper];

        if (_resizingImageNumber == 0 && _doneButtonClicked) {
          [self doneButtonAction:nil];
        }
      });
    });

    dispatch_release(queue);

    ++self.assetPickerState.selectedCount;
  }else {
    --self.assetPickerState.selectedCount;

    [self.assetPickerState changeSelectionState:selected forAsset:assetWrapper];
  }

  // Update the state object's selectedAssets.

  if (self.assetPickerState.selectedCount != 0) {
    [_doneBarButtonItem setTitle:[NSString stringWithFormat:@"完成(%d/%d)", self.assetPickerState.selectedCount, self.assetPickerState.selectionLimit]];
    _doneBarButtonItem.enabled = YES;
  } else {
    [_doneBarButtonItem setTitle:@"完成"];
    _doneBarButtonItem.enabled = NO;
  }
}

- (UIImage *)resizeAndSaveImage:(ALAsset *)asset {
  ALAssetRepresentation *representation = asset.defaultRepresentation;
  CGImageRef imageRef = [representation fullScreenImage];
  UIImage *bigImage = [UIImage imageWithCGImage:imageRef];

  UIImage *scaleImage = nil;
  if (bigImage.size.width > 640) {
    scaleImage = [bigImage imageWithScale:(640 / bigImage.size.width)];
  } else {
    scaleImage = bigImage;
  }

  return scaleImage;
}

- (NSString *)pathWithImageSaved:(UIImage *)image {
  NSData   *imageData = UIImageJPEGRepresentation(image, 0.7);
  NSString *sha1      = [imageData SHA1Sum];

  NSURL *imageTempDir = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
  imageTempDir = [imageTempDir URLByAppendingPathComponent:kWSSendImageTempDir];

  NSError *error = nil;

  if (![[NSFileManager defaultManager] fileExistsAtPath:imageTempDir.path]) {
    [[NSFileManager defaultManager] createDirectoryAtURL:imageTempDir withIntermediateDirectories:YES attributes:nil error:&error];

    if (error) {
      NSLog(@"%@", error);
    }
  }

  NSString *filename = [NSString stringWithFormat:@"%@.jpg", sha1];
  NSURL    *imageURL = [imageTempDir URLByAppendingPathComponent:filename];
  [imageData writeToFile:imageURL.path atomically:YES];

  return imageURL.path;
}


#pragma mark - Table view data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return (self.fetchedAssets.count + self.assetsPerRow - 1) / self.assetsPerRow;
}

- (NSArray *)assetsForIndexPath:(NSIndexPath *)indexPath {
  NSRange assetRange;
  assetRange.location = (NSUInteger) (indexPath.row * self.assetsPerRow);
  assetRange.length   = (NSUInteger) self.assetsPerRow;

  // Prevent the range from exceeding the array length.
  if (assetRange.length > self.fetchedAssets.count - assetRange.location) {
    assetRange.length = self.fetchedAssets.count - assetRange.location;
  }

  NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:assetRange];

  // Return the range of assets from fetchedAssets.
  return [self.fetchedAssets objectsAtIndexes:indexSet];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  static NSString       *AssetCellIdentifier = @"WSAssetCell";
  WSAssetsTableViewCell *cell                = [self.tableView dequeueReusableCellWithIdentifier:AssetCellIdentifier];

  if (cell == nil) {

    cell = [[WSAssetsTableViewCell alloc] initWithAssets:[self assetsForIndexPath:indexPath] reuseIdentifier:AssetCellIdentifier];
    cell.assetPickerState = self.assetPickerState;
  } else {

    cell.cellAssetViews = [self assetsForIndexPath:indexPath];
  }
  cell.delegate                              = self;

  return cell;
}


#pragma mark - Table view delegate

#define ROW_HEIGHT 79.0f

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
  return ROW_HEIGHT;
}

@end
