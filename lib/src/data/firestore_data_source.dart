import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:suggest_a_feature/suggest_a_feature.dart';

enum _Entity { suggestion, comment }

class FirestoreDataSource implements SuggestionsDataSource {
  static const String _suggestionIdFieldName = 'suggestion_id';
  static const String _authorIdFieldName = 'author_id';
  static const String _commentIdFieldName = 'comment_id';
  static const String _votedUsersArrayName = 'voted_user_ids';
  static const String _notificationsUsersArrayName = 'notify_user_ids';

  final String suggestionsCollectionPath;
  final String commentsCollectionPath;

  final FirebaseFirestore _firestoreInstance;

  @override
  final String userId;

  FirestoreDataSource({
    required this.userId,
    required FirebaseFirestore firestoreInstance,
    this.suggestionsCollectionPath = 'suggest_a_feature_suggestions',
    this.commentsCollectionPath = 'suggest_a_feature_comments',
  }) : _firestoreInstance = firestoreInstance;

  CollectionReference<Map<String, dynamic>> get _suggestions =>
      _firestoreInstance.collection(suggestionsCollectionPath);

  CollectionReference<Map<String, dynamic>> get _comments =>
      _firestoreInstance.collection(commentsCollectionPath);

  @override
  Future<Suggestion> getSuggestionById(String suggestionId) async {
    final response = await _suggestions.doc(suggestionId).get();
    final rawSuggestionData = _addEntityId(_Entity.suggestion, response);

    return Suggestion.fromJson(json: rawSuggestionData);
  }

  @override
  Future<List<Suggestion>> getAllSuggestions() async {
    final response = await _suggestions.get();

    return response.docs.isNotEmpty
        ? response.docs
            .map(
              (json) => Suggestion.fromJson(
                json: _addEntityId(_Entity.suggestion, json),
              ),
            )
            .toList()
        : [];
  }

  @override
  Future<Suggestion> createSuggestion(CreateSuggestionModel suggestion) async {
    final reference = await _suggestions.add(suggestion.toJson());
    final response = await _suggestions.doc(reference.id).get();

    return Suggestion.fromJson(
      json: _addEntityId(
        _Entity.suggestion,
        response,
      ),
    );
  }

  @override
  Future<Suggestion> updateSuggestion(Suggestion suggestion) async {
    if (!await _isUserAuthor(_Entity.suggestion, suggestion.id)) {
      throw Exception(
        'Failed to update the suggestion. User has no author rights',
      );
    }
    await _suggestions.doc(suggestion.id).update(suggestion.toUpdatingJson());

    return getSuggestionById(suggestion.id);
  }

  @override
  Future<void> deleteSuggestionById(String suggestionId) async {
    if (!await _isUserAuthor(_Entity.suggestion, suggestionId)) {
      throw Exception(
        'Failed to update the suggestion. User has no author rights',
      );
    }
    await _suggestions.doc(suggestionId).delete();
    await _commentsBatchDelete(suggestionId);
  }

  @override
  Future<List<Comment>> getAllComments(String suggestionId) async {
    final response = await _comments
        .where(_suggestionIdFieldName, isEqualTo: suggestionId)
        .get();

    return response.docs.isNotEmpty
        ? response.docs
            .map(
              (json) => Comment.fromJson(
                json: _addEntityId(_Entity.comment, json),
              ),
            )
            .toList()
        : [];
  }

  @override
  Future<Comment> createComment(CreateCommentModel comment) async {
    final commentReference = await _comments.add(comment.toJson());
    return _getCommentById(commentReference.id);
  }

  @override
  Future<void> deleteCommentById(String commentId) async {
    if (!await _isUserAuthor(_Entity.comment, commentId)) {
      throw Exception(
        'Failed to update the suggestion. User has no author rights',
      );
    }

    return _comments.doc(commentId).delete();
  }

  Future<Comment> _getCommentById(String commentId) async {
    final response = await _comments.doc(commentId).get();

    return Comment.fromJson(
      json: _addEntityId(
        _Entity.comment,
        response,
      ),
    );
  }

  Future<void> _commentsBatchDelete(String suggestionId) async {
    final batch = FirebaseFirestore.instance.batch();
    final comments = await _comments
        .where(_suggestionIdFieldName, isEqualTo: suggestionId)
        .get();
    for (final document in comments.docs) {
      batch.delete(document.reference);
    }
    batch.commit();
  }

  @override
  Future<void> addNotifyToUpdateUser(String suggestionId) async {
    final userIdsToNotify = await _getSuggestionNotifications(suggestionId);
    if (userIdsToNotify.contains(userId)) {
      throw Exception(
        'Failed to add notification. User is already in notify list',
      );
    }

    return _suggestions.doc(suggestionId).update({
      _notificationsUsersArrayName: [...userIdsToNotify, userId],
    });
  }

  @override
  Future<void> deleteNotifyToUpdateUser(String suggestionId) async {
    final userIdsToNotify = await _getSuggestionNotifications(suggestionId);
    if (!userIdsToNotify.contains(userId)) {
      throw Exception(
        'Failed to remove notification. User is not in notify list',
      );
    }
    userIdsToNotify.remove(userId);

    return _suggestions.doc(suggestionId).update({
      _notificationsUsersArrayName: userIdsToNotify,
    });
  }

  @override
  Future<void> upvote(String suggestionId) async {
    final votedUserIds = await _getSuggestionVotes(suggestionId);
    if (votedUserIds.contains(userId)) {
      throw Exception(
        'Failed to vote for the suggestion. User has already voted',
      );
    }

    return _suggestions.doc(suggestionId).update({
      _votedUsersArrayName: [...votedUserIds, userId]
    });
  }

  @override
  Future<void> downvote(String suggestionId) async {
    final votedUserIds = await _getSuggestionVotes(suggestionId);
    if (!votedUserIds.contains(userId)) {
      throw Exception(
        'Failed to remove the vote for the suggestion. '
        'User has not voted earlier',
      );
    }
    votedUserIds.remove(userId);

    return _suggestions.doc(suggestionId).update({
      _votedUsersArrayName: votedUserIds,
    });
  }

  Future<List<String>> _getSuggestionVotes(String suggestionId) async {
    final suggestionObject = await _suggestions.doc(suggestionId).get();
    final suggestion = suggestionObject.data();
    final votes = suggestion?[_votedUsersArrayName] as List<dynamic>?;

    return votes == null ? [] : votes.cast<String>();
  }

  Future<List<String>> _getSuggestionNotifications(String suggestionId) async {
    final suggestionObject = await _suggestions.doc(suggestionId).get();
    final suggestion = suggestionObject.data();
    final notifications =
        suggestion?[_notificationsUsersArrayName] as List<dynamic>?;

    return notifications == null ? [] : notifications.cast<String>();
  }

  Future<bool> _isUserAuthor(_Entity entity, String entityId) async {
    final QuerySnapshot<Map<String, dynamic>> response;

    switch (entity) {
      case _Entity.suggestion:
        response = await _suggestions
            .where(
              _authorIdFieldName,
              isEqualTo: userId,
            )
            .get();
        break;
      case _Entity.comment:
        response = await _comments
            .where(
              _authorIdFieldName,
              isEqualTo: userId,
            )
            .get();
        break;
    }

    final documents = response.docs.where((e) => e.id == entityId);

    return documents.length == 1;
  }

  Map<String, dynamic> _addEntityId(
    _Entity entity,
    DocumentSnapshot<Map<String, dynamic>> item,
  ) {
    final rawData = item.data();
    if (rawData == null) {
      throw Exception(
        'An error occurred while trying to retrieve the data from the '
        'database. The data returned was null, which is unexpected. ',
      );
    }
    switch (entity) {
      case _Entity.comment:
        rawData[_commentIdFieldName] = item.id;
        break;
      case _Entity.suggestion:
        rawData[_suggestionIdFieldName] = item.id;
        break;
    }

    return rawData;
  }
}
