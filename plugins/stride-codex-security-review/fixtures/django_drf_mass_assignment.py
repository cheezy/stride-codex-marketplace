# Vulnerable Django REST Framework serializer: fields = '__all__' on a
# model with privileged fields.
#
# Trust boundary: HTTP request body flows through UserSerializer.create /
# .update; because fields = '__all__' is set, every model attribute —
# including :is_staff, :is_superuser, :role — is writable by the client.
#
# Expected finding: authorization (high), CWE-915, A04:2021.

from django.db import models
from rest_framework import serializers, viewsets


class User(models.Model):
    email = models.EmailField()
    name = models.CharField(max_length=200)
    role = models.CharField(max_length=50, default="member")
    is_staff = models.BooleanField(default=False)
    is_superuser = models.BooleanField(default=False)
    owner_id = models.IntegerField(null=True)

    class Meta:
        app_label = "myapp"


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        # Vulnerable: '__all__' includes :is_staff, :is_superuser, :role,
        # :owner_id — privileged fields that should never be client-writable.
        # A request body of {"is_superuser": true, "role": "superuser"}
        # promotes the requester.
        fields = "__all__"


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all()
    serializer_class = UserSerializer
