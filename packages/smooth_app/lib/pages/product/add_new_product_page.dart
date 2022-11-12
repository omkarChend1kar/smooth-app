import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:openfoodfacts/model/Product.dart';
import 'package:openfoodfacts/model/ProductImage.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/database/dao_product.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/generic_lib/buttons/smooth_large_button_with_icon.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/pages/image_crop_page.dart';
import 'package:smooth_app/pages/product/add_basic_details_page.dart';
import 'package:smooth_app/pages/product/confirm_and_upload_picture.dart';
import 'package:smooth_app/pages/product/nutrition_page_loaded.dart';
import 'package:smooth_app/pages/product/ordered_nutrients_cache.dart';
import 'package:smooth_app/widgets/smooth_scaffold.dart';

const EdgeInsetsGeometry _ROW_PADDING_TOP = EdgeInsetsDirectional.only(
  top: VERY_LARGE_SPACE,
);

// Buttons to add images will appear in this order.
const List<ImageField> _SORTED_IMAGE_FIELD_LIST = <ImageField>[
  ImageField.FRONT,
  ImageField.NUTRITION,
  ImageField.INGREDIENTS,
  ImageField.PACKAGING,
  ImageField.OTHER,
];

class AddNewProductPage extends StatefulWidget {
  const AddNewProductPage(this.barcode);

  final String barcode;

  @override
  State<AddNewProductPage> createState() => _AddNewProductPageState();
}

class _AddNewProductPageState extends State<AddNewProductPage> {
  final Map<ImageField, List<File>> _uploadedImages =
      <ImageField, List<File>>{};

  late Product _product;
  late final Product _initialProduct;
  late final LocalDatabase _localDatabase;

  bool get _nutritionFactsAdded => _product.nutriments != null;
  bool get _basicDetailsAdded =>
      AddBasicDetailsPage.isProductBasicValid(_product);

  @override
  void initState() {
    super.initState();
    _initialProduct = Product(barcode: widget.barcode);
    _localDatabase = context.read<LocalDatabase>();
    _localDatabase.upToDate.showInterest(widget.barcode);
  }

  @override
  void dispose() {
    _localDatabase.upToDate.loseInterest(widget.barcode);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations appLocalizations = AppLocalizations.of(context);
    context.watch<LocalDatabase>();
    final ThemeData themeData = Theme.of(context);
    _product = _localDatabase.upToDate.getLocalUpToDate(_initialProduct);
    return SmoothScaffold(
      appBar: AppBar(
          title: Text(appLocalizations.new_product),
          automaticallyImplyLeading: _uploadedImages.isEmpty),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (_basicDetailsAdded ||
              _nutritionFactsAdded ||
              _uploadedImages.isNotEmpty) {
            // Tricky situation: we've launched background tasks,
            // but is at least one of them completed?
            final DaoProduct daoProduct = DaoProduct(_localDatabase);
            final Product? localProduct = await daoProduct.get(widget.barcode);
            // No background task was completed yet: we create a dummy product,
            // so that the pending changes can go on top of something.
            if (localProduct == null) {
              await daoProduct.put(_initialProduct);
              _localDatabase.upToDate
                  .setLatestDownloadedProduct(_initialProduct);
              _localDatabase.notifyListeners();
            }
          }
          if (!mounted) {
            return;
          }
          await Navigator.maybePop(context);
        },
        label: Text(appLocalizations.finish),
        icon: const Icon(Icons.done),
      ),
      body: Padding(
        padding: const EdgeInsetsDirectional.only(
          top: VERY_LARGE_SPACE,
          start: VERY_LARGE_SPACE,
          end: VERY_LARGE_SPACE,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                appLocalizations.add_product_take_photos_descriptive,
                style: themeData.textTheme.bodyText1!
                    .apply(color: themeData.colorScheme.onBackground),
              ),
              ..._buildImageCaptureRows(context),
              _buildNutritionInputButton(),
              _buildaddInputDetailsButton()
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildImageCaptureRows(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    // First build rows for buttons to ask user to upload images.
    for (final ImageField imageType in _SORTED_IMAGE_FIELD_LIST) {
      // Always add a button to "Add other photos" because there can be multiple
      // "other photos" uploaded by the user.
      if (imageType == ImageField.OTHER) {
        rows.add(_buildAddImageButton(context, imageType));
        if (_uploadedImages[imageType] != null) {
          for (final File image in _uploadedImages[imageType]!) {
            rows.add(_buildImageUploadedRow(context, imageType, image));
          }
        }
        continue;
      }

      // Everything else can only be uploaded once
      if (_isImageUploadedForType(imageType)) {
        rows.add(
          _buildImageUploadedRow(
            context,
            imageType,
            _uploadedImages[imageType]![0],
          ),
        );
      } else {
        rows.add(_buildAddImageButton(context, imageType));
      }
    }
    return rows;
  }

  Widget _buildAddImageButton(BuildContext context, ImageField imageType) {
    return Padding(
      padding: _ROW_PADDING_TOP,
      child: SmoothLargeButtonWithIcon(
        text: _getAddPhotoButtonText(context, imageType),
        icon: Icons.camera_alt,
        onPressed: () async {
          final File? initialPhoto = await startImageCropping(this);
          if (initialPhoto == null) {
            return;
          }
          // Photo can change in the ConfirmAndUploadPicture widget, the user
          // may choose to retake the image.
          // TODO(monsieurtanuki): careful, waiting for pop'ed value
          //ignore: use_build_context_synchronously
          final File? finalPhoto = await Navigator.push<File?>(
            context,
            MaterialPageRoute<File?>(
              builder: (BuildContext context) => ConfirmAndUploadPicture(
                barcode: widget.barcode,
                imageType: imageType,
                initialPhoto: initialPhoto,
              ),
            ),
          );
          if (finalPhoto != null) {
            _uploadedImages[imageType] = _uploadedImages[imageType] ?? <File>[];
            _uploadedImages[imageType]!.add(initialPhoto);
          }
        },
      ),
    );
  }

  Widget _buildImageUploadedRow(
      BuildContext context, ImageField imageType, File image) {
    return _InfoAddedRow(
      text: _getAddPhotoButtonText(context, imageType),
      imgStart: image,
    );
  }

  String _getAddPhotoButtonText(BuildContext context, ImageField imageType) {
    final AppLocalizations appLocalizations = AppLocalizations.of(context);
    switch (imageType) {
      case ImageField.FRONT:
        return appLocalizations.front_packaging_photo_button_label;
      case ImageField.INGREDIENTS:
        return appLocalizations.ingredients_photo_button_label;
      case ImageField.NUTRITION:
        return appLocalizations.nutritional_facts_photo_button_label;
      case ImageField.PACKAGING:
        return appLocalizations.recycling_photo_button_label;
      case ImageField.OTHER:
        return appLocalizations.other_interesting_photo_button_label;
    }
  }

  bool _isImageUploadedForType(ImageField imageType) {
    return (_uploadedImages[imageType] ?? <File>[]).isNotEmpty;
  }

  Widget _buildNutritionInputButton() {
    // if the nutrition image is null, ie no image , we return nothing
    if (_product.imageNutritionUrl == null) {
      return const SizedBox();
    }
    if (_nutritionFactsAdded) {
      return _InfoAddedRow(
          text: AppLocalizations.of(context).nutritional_facts_added);
    }

    return Padding(
      padding: _ROW_PADDING_TOP,
      child: SmoothLargeButtonWithIcon(
        text: AppLocalizations.of(context).nutritional_facts_input_button_label,
        icon: Icons.edit,
        onPressed: () async {
          final OrderedNutrientsCache? cache =
              await OrderedNutrientsCache.getCache(context);
          if (!mounted) {
            return;
          }
          if (cache == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    AppLocalizations.of(context).nutrition_cache_loading_error),
              ),
            );
            return;
          }
          await Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (BuildContext context) => NutritionPageLoaded(
                Product(barcode: widget.barcode),
                cache.orderedNutrients,
                isLoggedInMandatory: false,
              ),
              fullscreenDialog: true,
            ),
          );
        },
      ),
    );
  }

  Widget _buildaddInputDetailsButton() {
    if (_basicDetailsAdded) {
      return _InfoAddedRow(
          text: AppLocalizations.of(context).basic_details_add_success);
    }

    return Padding(
      padding: _ROW_PADDING_TOP,
      child: SmoothLargeButtonWithIcon(
        text: AppLocalizations.of(context).completed_basic_details_btn_text,
        icon: Icons.edit,
        onPressed: () async => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (BuildContext context) => AddBasicDetailsPage(
              Product(barcode: widget.barcode),
              isLoggedInMandatory: false,
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoAddedRow extends StatelessWidget {
  const _InfoAddedRow({required this.text, this.imgStart});

  final String text;
  final File? imgStart;

  @override
  Widget build(BuildContext context) {
    final ThemeData themeData = Theme.of(context);
    return Padding(
      padding: _ROW_PADDING_TOP,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            height: 50,
            width: 50,
            child: ClipRRect(
              borderRadius: ROUNDED_BORDER_RADIUS,
              child: imgStart == null
                  ? null
                  : Image.file(imgStart!, fit: BoxFit.cover),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(text, style: themeData.textTheme.bodyText1),
            ),
          ),
          Icon(
            Icons.check,
            color: themeData.bottomNavigationBarTheme.selectedItemColor,
          )
        ],
      ),
    );
  }
}
