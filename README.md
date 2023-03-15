# Suggest a Feature Firestore

This package is a data source extension for
[suggest_a_feature](https://pub.dev/packages/suggest_a_feature) package.

<p align="center">
  <a href="https://pub.dartlang.org/packages/suggest_a_feature_firestore">
    <img alt="Pub" src="https://img.shields.io/pub/v/suggest_a_feature_firestore"/>
  </a>
  <a href="https://github.com/What-the-Flutter/Suggest-a-Feature-Firestore/actions/workflows/build.yml?query=workflow%3ABuild">
    <img alt="Build Status" src="https://github.com/What-the-Flutter/Suggest-a-Feature-Firestore/actions/workflows/build.yml/badge.svg?event=push"/>
  </a>
  <a href="https://www.codefactor.io/repository/github/what-the-flutter/suggest-a-feature-firestore">
    <img alt="CodeFactor" src="https://www.codefactor.io/repository/github/what-the-flutter/suggest-a-feature-firestore/badge"/>
  </a>
</p>

## Getting started

```yaml
dependencies:
  suggest_a_feature: ^latest version
  suggest_a_feature_firestore: ^latest version
```

You need to add Firebase to your project following steps described in this link from official firebase website:
<https://console.firebase.google.com/>

## Usage

You need to place `FirestoreDataSource` class as a `suggestionsDataSource` field in `SuggestionsPage` widget. Don't forget to place `FirebaseFirestore.instance` as `firestoreInstance` field in `FirestoreDataSource` class.
For example:

```dart
SuggestionsPage(
  userId: '1',
  suggestionsDataSource: FirestoreDataSource(
    userId: '1',
    firestoreInstance: FirebaseFirestore.instance,
  ),
  theme: SuggestionsTheme.initial() ,
  onUploadMultiplePhotos: null,
  onSaveToGallery: null,
  onGetUserById: () {},
);
```

## Firestore rules

You also must add following rules to your *Firestore* in *Firebase Console*:

```dart
match /suggest_a_feature_suggestions/{suggest_a_feature_suggestion}{
  allow read, write: if request.auth != null;
}

match /suggest_a_feature_comments/{suggest_a_feature_comment}{
  allow read, write: if request.auth != null;
}
```

* only if those rules are not defined for all lists

## Pay your attention

For each delete or update suggestion action we check either user have author rights to fulfil those actions. Author rights is such a concept that only the user who created a suggestion can manipulate it (delete or update it). If somehow happens the situation when user without author rights will try to delete/update a suggestion will be thrown an Exception

We provide batch deleting of all the comments related to deleting suggestion in order save storage place and keep your firestore collections clean.

## Cloud Firestore

Data collections names in firebase firestore will be the following ones:

* **suggest_a_feature_suggestions** for suggestions collection
* **suggest_a_feature_comments** for comments collection
